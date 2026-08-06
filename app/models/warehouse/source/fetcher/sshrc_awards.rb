# Downloads each yearly SSHRC payments CSV advertised by the Open Government
# catalogue and converts its changing bilingual schema into one canonical CSV.
class Warehouse::Source::Fetcher::SshrcAwards
  YearDownload = Data.define(:year, :url, :io, :checksum)

  CATALOGUE_URL = "https://open.canada.ca/data/api/action/package_show?id=b4e2b302-9bc6-4b33-b880-6496f8cef0f1".freeze
  DETAIL_URL = "http://www.outil.ost.uqam.ca/CRSH/Detail.aspx".freeze
  PAYMENT_RESOURCE_NAME = /\A(?<year>\d{4}) Payments\z/i
  OUTPUT_HEADERS = %w[
    external_id application_id recipient_name recipient_organization recipient_role
    title description award_amount fiscal_year competition_year program discipline
    main_discipline area_of_research keywords province country source_url source_fields
  ].freeze

  def initialize(url = CATALOGUE_URL, http: HTTPX.plugin(:stream).plugin(:follow_redirects), years: nil)
    @url = url
    @http = http
    @years = Array(years).map { |year| Integer(year) }.to_set if years
  end

  def each_year
    return enum_for(__method__) unless block_given?

    payments = catalogue_resources.filter_map { |resource| payment_resource(resource) }
    payments.select! { |year, _url| @years.include?(year) } if @years
    raise "SSHRC catalogue contains no yearly payment CSVs: #{@url}" if payments.empty?

    payments.sort_by(&:first).each do |year, url|
      yield download_year(year, url)
    end
  end

  def each_download
    return enum_for(__method__) unless block_given?

    each_year do |result|
      year = result.year
      download = Warehouse::Source::Fetcher::Download.new(
        body: result.io,
        checksum: result.checksum,
        filename: "sshrc-awards-#{year}-#{result.checksum.first(12)}.csv"
      ) do |ingestion, content|
        ingestion.spending_loader.load(body: content, withdrawal_scope: { fiscal_year: year })
      end
      yield download
    end
  end

  private

  def catalogue_resources
    response = @http.get(@url)
    raise "HTTP #{response.status}: #{@url}" unless response.status == 200

    document = JSON.parse(response.body.to_s.delete_prefix("\uFEFF"))
    resources = document.dig("result", "resources") if document["success"]
    raise "Unexpected SSHRC catalogue response: #{@url}" unless resources.is_a?(Array)

    resources
  rescue JSON::ParserError => error
    raise "Invalid SSHRC catalogue JSON for #{@url}: #{error.message}"
  end

  def payment_resource(resource)
    match = resource["name"].to_s.match(PAYMENT_RESOURCE_NAME)
    return unless match && resource["format"].to_s.casecmp?("CSV") && resource["url"].present?

    [ Integer(match[:year]), resource.fetch("url") ]
  end

  def download_year(year, url)
    # Several legacy catalogue entries contain literal spaces, while newer
    # entries are already escaped. Avoid double-escaping the latter.
    request_url = url.sub(/\Ahttp:\/\/www\.sshrc-crsh\.gc\.ca/i, "https://www.sshrc-crsh.gc.ca")
      .gsub(" ", "%20")
    response = @http.get(request_url, stream: true)
    raise "HTTP #{response.status}: #{request_url}" unless response.status == 200

    raw_file = Tempfile.new([ "sshrc-#{year}-raw", ".csv" ])
    raw_file.binmode
    response.each { |chunk| raw_file.write(chunk) }
    raw_file.rewind
    set_text_encoding(raw_file)

    output = Tempfile.new([ "sshrc-#{year}", ".csv" ])
    output.binmode
    writer = CSV.new(output)
    writer << OUTPUT_HEADERS

    id_counts = count_and_validate_ids(raw_file, year)
    raw_file.rewind
    duplicate_counts = Hash.new(0)
    CSV.new(raw_file, headers: true, liberal_parsing: true).each_with_index do |row, index|
      normalized = normalized_row(row.to_h, year, url, id_counts, duplicate_counts)
      writer << normalized.values_at(*OUTPUT_HEADERS)
    end
    writer.close
    output.open
    output.set_encoding(Encoding::UTF_8)
    checksum = Digest::SHA256.file(output.path).hexdigest
    output.rewind

    YearDownload.new(year:, url:, io: output, checksum:)
  rescue CSV::MalformedCSVError => error
    output&.close!
    raise "Invalid SSHRC CSV for #{url}: #{error.message}"
  rescue
    output&.close!
    raise
  ensure
    raw_file&.close!
  end

  def normalized_row(row, catalogue_year, url, id_counts, duplicate_counts)
    values = row.to_h.to_h { |header, value| [ normalized_header(header), clean_value(value) ] }
    award_id = field(values, "cle")

    {
      "external_id" => external_id(award_id, row, id_counts, duplicate_counts),
      "application_id" => field(values, "filenumber"),
      "recipient_name" => field(values, "namenom"),
      "recipient_organization" => field(values, "institution"),
      "recipient_role" => field(values, "role", "rolerole"),
      "title" => field(values, "title", "titletitre"),
      "description" => nil,
      "award_amount" => field(values, "awardamount", "amountmontant"),
      "fiscal_year" => field(values, "fiscalyearexercicefinancier") || catalogue_year,
      "competition_year" => field(values, "competitionyear", "competitionyearanneeduconcours"),
      "program" => field(values, "programnameen", "program"),
      "discipline" => field(values, "disciplineen", "sshrcdisciplineen"),
      "main_discipline" => field(values, "maindisciplineen", "maindiscipline", "sshrcmaindiscipline"),
      "area_of_research" => field(values, "areaofresearchen", "areaofresearch", "sshrcareaofresearch"),
      "keywords" => field(values, "keywords", "keywordsmotscles"),
      "province" => field(values, "provinceen"),
      "country" => "Canada",
      "source_url" => "#{DETAIL_URL}?Cle=#{CGI.escape(award_id)}&Langue=2",
      "source_fields" => row.to_h.compact.merge("_resource_url" => url).to_json
    }
  end

  def count_and_validate_ids(file, year)
    counts = Hash.new(0)
    CSV.new(file, headers: true, liberal_parsing: true).each_with_index do |row, index|
      values = row.to_h.to_h { |header, value| [ normalized_header(header), clean_value(value) ] }
      id = field(values, "cle")
      unless id.to_s.match?(/\A\d+\z/)
        raise "SSHRC #{year} payment on line #{index + 2} has an invalid award id"
      end
      counts[id] += 1
    end
    counts
  end

  def external_id(award_id, row, id_counts, duplicate_counts)
    return award_id if id_counts.fetch(award_id) == 1

    digest = Digest::SHA256.hexdigest(row.to_h.values.join("\u001F")).first(16)
    base = "#{award_id}-#{digest}"
    duplicate_counts[base] += 1
    duplicate_counts[base] == 1 ? base : "#{base}-#{duplicate_counts[base]}"
  end

  def normalized_header(header)
    header.to_s.delete_prefix("\uFEFF").strip.unicode_normalize(:nfkd)
      .gsub(/\p{Mn}/, "").downcase.gsub(/[^a-z0-9]/, "")
  end

  def field(values, *names)
    names.each do |name|
      value = values[name]
      return value if value.present?
    end
    nil
  end

  def clean_value(value)
    value.to_s.strip.presence
  end

  def set_text_encoding(file)
    sample = file.read(65_536).to_s
    file.rewind

    if sample.start_with?("\xEF\xBB\xBF".b)
      file.pos = 3
      file.set_encoding(Encoding::UTF_8)
    elsif sample.start_with?("\xFF\xFE".b)
      file.pos = 2
      file.set_encoding(Encoding::UTF_16LE, Encoding::UTF_8, invalid: :replace, undef: :replace)
    elsif sample.start_with?("\xFE\xFF".b)
      file.pos = 2
      file.set_encoding(Encoding::UTF_16BE, Encoding::UTF_8, invalid: :replace, undef: :replace)
    elsif sample.dup.force_encoding(Encoding::UTF_8).valid_encoding?
      file.set_encoding(Encoding::UTF_8)
    else
      file.set_encoding(Encoding::Windows_1252, Encoding::UTF_8, invalid: :replace, undef: :replace)
    end
  end
end
