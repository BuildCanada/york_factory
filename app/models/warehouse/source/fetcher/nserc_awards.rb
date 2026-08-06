# Downloads each yearly awards CSV advertised by NSERC's Open Government
# catalogue as an independent canonical stream. A failed year does not discard
# or delay the years that were already downloaded and ingested.
class Warehouse::Source::Fetcher::NsercAwards
  YearDownload = Data.define(:year, :url, :io, :checksum)
  AWARD_RESOURCE_NAME = /\A(?<year>\d{4}) Awards\z/i
  OUTPUT_HEADERS = %w[
    external_id application_id recipient_name recipient_organization title description
    award_amount fiscal_year competition_year installment program program_id department
    selection_committee research_subject province country source_url source_fields
  ].freeze

  def initialize(url, http: HTTPX.plugin(:stream).plugin(:follow_redirects), years: nil)
    @url = url
    @http = http
    @years = Array(years).map { |year| Integer(year) }.to_set if years
  end

  def each_year
    return enum_for(__method__) unless block_given?

    resources = catalogue_resources
    awards = resources.filter_map { |resource| award_resource(resource) }
    awards.select! { |year, _url| @years.include?(year) } if @years
    raise "NSERC catalogue contains no yearly award CSVs: #{@url}" if awards.empty?

    awards.sort_by(&:first).each do |year, url|
      yield download_year(year, url)
    end
  end

  private

  def catalogue_resources
    response = @http.get(@url)
    raise "HTTP #{response.status}: #{@url}" unless response.status == 200

    document = JSON.parse(response.body.to_s.delete_prefix("\uFEFF"))
    resources = document.dig("result", "resources") if document["success"]
    raise "Unexpected NSERC catalogue response: #{@url}" unless resources.is_a?(Array)

    resources
  rescue JSON::ParserError => error
    raise "Invalid NSERC catalogue JSON for #{@url}: #{error.message}"
  end

  def award_resource(resource)
    match = resource["name"].to_s.match(AWARD_RESOURCE_NAME)
    return unless match && resource["format"].to_s.casecmp?("CSV") && resource["url"].present?

    [ Integer(match[:year]), resource.fetch("url") ]
  end

  def download_year(year, url)
    response = @http.get(url, stream: true)
    raise "HTTP #{response.status}: #{url}" unless response.status == 200

    raw_file = Tempfile.new([ "nserc-#{year}-raw", ".csv" ])
    raw_file.binmode
    response.each { |chunk| raw_file.write(chunk) }
    raw_file.rewind
    set_text_encoding(raw_file)

    output = Tempfile.new([ "nserc-#{year}", ".csv" ])
    output.binmode
    writer = CSV.new(output)
    writer << OUTPUT_HEADERS

    identity_counts = count_identities(raw_file, year)
    raw_file.binmode
    raw_file.rewind
    set_text_encoding(raw_file)
    duplicate_counts = Hash.new(0)
    CSV.new(raw_file, headers: true, liberal_parsing: true).each do |row|
      normalized = normalized_row(row.to_h, year, url, identity_counts, duplicate_counts)
      writer << normalized.values_at(*OUTPUT_HEADERS)
    end
    writer.close
    output.open
    output.binmode
    checksum = Digest::SHA256.file(output.path).hexdigest
    output.rewind

    YearDownload.new(year:, url:, io: output, checksum:)
  rescue CSV::MalformedCSVError => error
    output&.close!
    raise "Invalid NSERC CSV for #{url}: #{error.message}"
  rescue
    output&.close!
    raise
  ensure
    raw_file&.close!
  end

  def normalized_row(row, catalogue_year, url, identity_counts, duplicate_counts)
    fiscal_year = value(row, "FiscalYear-Exercice financier", "FiscalYear-Exercice-financier") || catalogue_year
    application_id = value(row, "ApplicationID")
    base_identity = application_identity(application_id, fiscal_year)
    identity = external_identity(base_identity, fiscal_year, row, identity_counts, duplicate_counts)

    {
      "external_id" => identity,
      "application_id" => application_id,
      "recipient_name" => value(row, "Name-Nom"),
      "recipient_organization" => value(row, "Institution-Établissement", "Institution-�tablissement"),
      "title" => value(row, "ApplicationTitle"),
      "description" => value(row, "ApplicationSummary"),
      "award_amount" => value(row, "AwardAmount"),
      "fiscal_year" => fiscal_year,
      "competition_year" => value(row, "CompetitionYear", "CompetitionYear-Année de concours"),
      "installment" => value(row, "Installment", "Part-Partie", "Nb_Partie"),
      "program" => value(row, "ProgramNameEN", "ProgramNaneEN"),
      "program_id" => value(row, "ProgramID"),
      "department" => value(row, "Department-Département", "Department"),
      "selection_committee" => value(row, "CommitteeNameEN", "SelectionCommitteeEN"),
      "research_subject" => value(row, "ResearchSubjectEN", "ResearchSubject"),
      "province" => value(row, "ProvinceEN"),
      "country" => value(row, "CountryEN"),
      "source_url" => url,
      "source_fields" => row.compact.to_json
    }
  end

  def count_identities(raw_file, catalogue_year)
    counts = Hash.new(0)
    CSV.new(raw_file, headers: true, liberal_parsing: true).each do |row|
      fiscal_year = value(row, "FiscalYear-Exercice financier", "FiscalYear-Exercice-financier") || catalogue_year
      identity = application_identity(value(row, "ApplicationID"), fiscal_year)
      counts[identity] += 1 if identity
    end
    counts
  end

  def application_identity(application_id, fiscal_year)
    return if application_id.blank? || application_id == "NA"

    "#{application_id}-#{fiscal_year}"
  end

  def external_identity(base_identity, fiscal_year, row, identity_counts, duplicate_counts)
    digest = Digest::SHA256.hexdigest(row.values.join("\u001F"))
    prefix = if base_identity
      return base_identity if identity_counts.fetch(base_identity) == 1

      "#{base_identity}-#{digest.first(16)}"
    else
      "unidentified-#{fiscal_year}-#{digest}"
    end
    duplicate_counts[prefix] += 1
    duplicate_counts[prefix] == 1 ? prefix : "#{prefix}-#{duplicate_counts[prefix]}"
  end

  def value(row, *names)
    names.each do |name|
      value = row[name]
      return value if value.present?
    end
    nil
  end

  def set_text_encoding(file)
    sample = file.read(65_536).to_s.dup.force_encoding(Encoding::UTF_8)
    file.rewind
    if sample.valid_encoding?
      file.pos = 3 if sample.start_with?("\uFEFF")
      file.set_encoding(Encoding::UTF_8)
    else
      file.set_encoding(Encoding::Windows_1252, Encoding::UTF_8, invalid: :replace, undef: :replace)
    end
  end
end
