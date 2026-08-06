# Streams each English yearly transfer-payment CSV advertised by the Open
# Government catalogue. Catalogue years are fiscal-year end years: the 2025
# resource contains records for 2024/2025, which we store as fiscal_year 2024.
class Warehouse::Source::Fetcher::TransferPayments
  YearDownload = Data.define(:year, :fiscal_year, :url, :io, :checksum)

  CATALOGUE_URL = "https://open.canada.ca/data/api/action/package_show?id=69bdc3eb-e919-4854-bc52-a435a3e19092".freeze
  RESOURCE_NAME = /\A(?<year>\d{4})\s*-\s*Transfer Payments\s*\z/i

  def initialize(url = CATALOGUE_URL, http: HTTPX.plugin(:stream).plugin(:follow_redirects), years: nil)
    @url = url
    @http = http
    @years = Array(years).map { |year| Integer(year) }.to_set if years
  end

  def each_year
    return enum_for(__method__) unless block_given?

    resources = catalogue_resources.filter_map { |resource| transfer_resource(resource) }
    resources.select! { |year, _url| @years.include?(year) } if @years
    raise "Transfer-payment catalogue contains no English yearly CSVs: #{@url}" if resources.empty?

    resources.sort_by(&:first).each do |year, url|
      yield download_year(year, url)
    end
  end

  def each_download
    return enum_for(__method__) unless block_given?

    each_year do |result|
      fiscal_year = result.fiscal_year
      download = Warehouse::Source::Fetcher::Download.new(
        body: result.io,
        checksum: result.checksum,
        filename: "transfer-payments-#{result.year}-#{result.checksum.first(12)}.csv"
      ) do |ingestion, content|
        ingestion.spending_loader.load(body: content, withdrawal_scope: { fiscal_year: })
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
    raise "Unexpected transfer-payment catalogue response: #{@url}" unless resources.is_a?(Array)

    resources
  rescue JSON::ParserError => error
    raise "Invalid transfer-payment catalogue JSON for #{@url}: #{error.message}"
  end

  def transfer_resource(resource)
    match = resource["name"].to_s.match(RESOURCE_NAME)
    url = resource["url"].to_s
    return unless match && resource["format"].to_s.casecmp?("CSV") && url.present?
    return if url.match?(/-fra\.csv(?:\?|\z)/i)

    [ Integer(match[:year]), url ]
  end

  def download_year(year, url)
    download = Warehouse::Source::Fetcher::StreamingDownload.new(url, http: @http).call
    YearDownload.new(
      year:,
      fiscal_year: year - 1,
      url:,
      io: download.io,
      checksum: download.checksum
    )
  rescue
    download&.io&.close!
    raise
  end
end
