# Downloads Global Affairs Canada's six official IATI activity files and
# normalizes them to a single, streaming-friendly CSV. These are the source
# files used by Project Browser and are updated every business day.
class Warehouse::Source::Fetcher::GlobalAffairsProjects
  Download = Data.define(:io, :checksum)

  BASE_URL = "https://w05.international.gc.ca/projectbrowser-banqueprojets/iita-iati".freeze
  DEFAULT_URLS = %w[2 3 4 4a 4b 4c].to_h { |status|
    [ status, "#{BASE_URL}/dfatd-maecd_activit_status_#{status}.xml" ]
  }.freeze
  OUTPUT_HEADERS = %w[
    external_id title description implementing_organizations start_date end_date
    commitment_amount currency status aid_type collaboration_type finance_type
    countries regions sectors policy_markers results detail_url source_url source_fields
  ].freeze
  XML_READER_OPTIONS = Nokogiri::XML::ParseOptions::STRICT |
    Nokogiri::XML::ParseOptions::NONET |
    Nokogiri::XML::ParseOptions::BIG_LINES

  def initialize(url = nil, urls: nil, http: HTTPX.plugin(:stream).plugin(:follow_redirects))
    @urls = normalized_urls(url, urls)
    @http = http
  end

  def call
    output = Tempfile.new([ "global-affairs-projects", ".csv" ])
    output.binmode
    writer = CSV.new(output)
    writer << OUTPUT_HEADERS
    identifiers = Set.new
    activity_count = 0

    @urls.each_value do |url|
      raw_file = download(url)
      begin
        each_activity(raw_file, url) do |activity|
          row = normalized_activity(activity, url)
          identifier = row.fetch("external_id")
          raise "Global Affairs IATI activity without an identifier in #{url}" if identifier.blank?
          raise "Duplicate Global Affairs IATI activity identifier: #{identifier}" unless identifiers.add?(identifier)

          writer << OUTPUT_HEADERS.map { |header| row[header] }
          activity_count += 1
        end
      ensure
        raw_file.close!
      end
    end

    raise "Global Affairs IATI files contained no activities" if activity_count.zero?

    writer.flush
    output.flush
    checksum = Digest::SHA256.file(output.path).hexdigest
    output.rewind
    Download.new(io: output, checksum: checksum)
  rescue
    output&.close!
    raise
  end

  private

  def normalized_urls(url, urls)
    values = urls || (url.to_s.end_with?(".xml") ? { "activity" => url } : DEFAULT_URLS)
    values = values.each_with_index.to_h { |value, index| [ index.to_s, value ] } unless values.respond_to?(:each_pair)
    values.to_h.transform_keys(&:to_s).transform_values(&:to_s)
  end

  def download(url)
    response = @http.get(url, stream: true)
    raise "HTTP #{response.status}: #{url}" unless response.status == 200

    file = Tempfile.new([ "global-affairs-iati", ".xml" ])
    file.binmode
    response.each { |chunk| file.write(chunk) }
    file.flush
    file.rewind
    file
  rescue
    file&.close!
    raise
  end

  # XMLReader keeps the roughly 95 MB source set off the Ruby heap. Only the
  # current activity is materialized so its nested IATI structures can be
  # normalized before the reader advances.
  def each_activity(file, url)
    reader = Nokogiri::XML::Reader(file, url, "UTF-8", XML_READER_OPTIONS)
    reader.each do |node|
      next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.name == "iati-activity"

      document = Nokogiri::XML(node.outer_xml) { |config| config.strict.nonet }
      yield document.root
    end
  rescue Nokogiri::XML::SyntaxError => error
    raise "Invalid Global Affairs IATI XML from #{url}: #{error.message}"
  end

  def normalized_activity(activity, source_url)
    identifier = clean(activity.at_xpath("iati-identifier")&.text)
    commitment_amount, currency = commitment(activity, identifier)

    {
      "external_id" => identifier,
      "title" => narrative(activity.at_xpath("title")),
      "description" => narrative(activity.at_xpath("description[@type='1']") || activity.at_xpath("description")),
      "implementing_organizations" => JSON.generate(organizations(activity)),
      "start_date" => activity_date(activity, actual: "2", planned: "1"),
      "end_date" => activity_date(activity, actual: "4", planned: "3"),
      "commitment_amount" => commitment_amount,
      "currency" => currency,
      "status" => activity.at_xpath("activity-status")&.[]("code"),
      "aid_type" => activity.at_xpath("default-aid-type")&.[]("code"),
      "collaboration_type" => activity.at_xpath("collaboration-type")&.[]("code"),
      "finance_type" => activity.at_xpath("default-finance-type")&.[]("code"),
      "countries" => JSON.generate(elements(activity, "recipient-country", %w[code percentage])),
      "regions" => JSON.generate(elements(activity, "recipient-region", %w[code percentage vocabulary vocabulary-uri])),
      "sectors" => JSON.generate(elements(activity, "sector", %w[code percentage vocabulary vocabulary-uri])),
      "policy_markers" => JSON.generate(elements(activity, "policy-marker", %w[code significance vocabulary vocabulary-uri])),
      "results" => JSON.generate(results(activity)),
      "detail_url" => detail_url(activity),
      "source_url" => source_url,
      "source_fields" => JSON.generate(source_fields(activity))
    }
  end

  def organizations(activity)
    activity.xpath("participating-org[@role='4']").map do |node|
      attributes(node, %w[role ref type crs-channel-code]).merge("name" => narrative(node)).compact
    end
  end

  def activity_date(activity, actual:, planned:)
    node = activity.at_xpath("activity-date[@type='#{actual}']") || activity.at_xpath("activity-date[@type='#{planned}']")
    node&.[]("iso-date")
  end

  def commitment(activity, identifier)
    values = activity.xpath("transaction[transaction-type/@code='2']/value")
    currencies = values.filter_map { |value| value["currency"].presence || activity["default-currency"].presence }.uniq
    if currencies.many?
      raise "Global Affairs activity #{identifier} has commitments in multiple currencies: #{currencies.join(', ')}"
    end

    amounts = values.filter_map { |value| decimal(value.text) }
    total = amounts.sum(BigDecimal("0")) if amounts.any?
    [ total&.to_s("F"), currencies.first || activity["default-currency"] ]
  end

  def decimal(value)
    BigDecimal(value.to_s.strip)
  rescue ArgumentError
    nil
  end

  def elements(activity, name, attribute_names)
    activity.xpath(name).map do |node|
      attributes(node, attribute_names).merge("name" => narrative(node)).compact
    end
  end

  def attributes(node, names)
    names.to_h { |name| [ name.tr("-", "_"), clean(node[name]) ] }.compact
  end

  def results(activity)
    activity.xpath("result").map do |result|
      {
        "type" => result["type"],
        "aggregation_status" => result["aggregation-status"],
        "title" => narrative(result.at_xpath("title")),
        "description" => narrative(result.at_xpath("description")),
        "indicators" => result.xpath("indicator").map { |indicator| indicator_result(indicator) }
      }.compact
    end
  end

  def indicator_result(indicator)
    {
      "measure" => indicator["measure"],
      "ascending" => indicator["ascending"],
      "title" => narrative(indicator.at_xpath("title")),
      "description" => narrative(indicator.at_xpath("description")),
      "baseline" => value_node(indicator.at_xpath("baseline")),
      "periods" => indicator.xpath("period").map do |period|
        {
          "start_date" => period.at_xpath("period-start")&.[]("iso-date"),
          "end_date" => period.at_xpath("period-end")&.[]("iso-date"),
          "target" => value_node(period.at_xpath("target")),
          "actual" => value_node(period.at_xpath("actual"))
        }.compact
      end
    }.compact
  end

  def value_node(node)
    return unless node

    {
      "value" => node["value"],
      "year" => node["year"],
      "comment" => narrative(node.at_xpath("comment"))
    }.compact.presence
  end

  def detail_url(activity)
    links = activity.xpath("document-link")
    link = links.find do |candidate|
      candidate.xpath("category").any? { |category| %w[A02 A08].include?(category["code"]) } &&
        candidate.xpath("language").any? { |language| language["code"].to_s.start_with?("en") }
    end
    link ||= links.find { |candidate| candidate["url"].to_s.include?("/details/") }
    clean(link&.[]("url"))
  end

  def source_fields(activity)
    reporting_org = activity.at_xpath("reporting-org")
    {
      "default_currency" => activity["default-currency"],
      "humanitarian" => activity["humanitarian"],
      "activity_scope" => activity.at_xpath("activity-scope")&.[]("code"),
      "reporting_organization" => reporting_org && attributes(reporting_org, %w[ref type]).merge("name" => narrative(reporting_org)).compact,
      "other_identifiers" => activity.xpath("other-identifier").map { |node| attributes(node, %w[ref type owner-org-ref]) }
    }.compact
  end

  def narrative(node)
    return unless node

    narratives = node.xpath("narrative")
    selected = narratives.find { |item| language(item).to_s.start_with?("en") } ||
      narratives.find { |item| language(item).blank? } || narratives.first
    clean(selected&.text || node.text)
  end

  def language(node)
    node.attribute_with_ns("lang", "http://www.w3.org/XML/1998/namespace")&.value
  end

  def clean(value)
    value.to_s.gsub(/[[:space:]]+/, " ").strip.presence
  end
end
