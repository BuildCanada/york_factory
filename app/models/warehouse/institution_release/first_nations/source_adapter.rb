require "cgi"
require "fileutils"
require "json"
require "net/http"
require "nokogiri"
require "securerandom"
require "set"
require "uri"

module Warehouse::InstitutionRelease::FirstNations
  class SourceAdapter
    class SourceError < StandardError; end

    DEFAULT_OUTPUT_ROOT = Pathname("/Volumes/floppy/york_factory/public_institutions/sources/first-nations")
    ISC_LOCATION_EN = "https://services.sac-isc.gc.ca/geomatics/rest/services/agol_feature_services/first_nations_aboriginal_lands_e/MapServer/0/query"
    ISC_LOCATION_FR = "https://services.sac-isc.gc.ca/geomatics/rest/services/agol_feature_services/first_nations_aboriginal_lands_f/MapServer/0/query"
    FNP_PROFILE = "https://services.sac-isc.gc.ca/fnp/Main/Search/FNMain.aspx"
    FNFTA_LIST = "https://services.sac-isc.gc.ca/fnp/Main/Search/FederalFundingMain.aspx"
    STATCAN_CSD_EN = "https://geo.statcan.gc.ca/geo_wa/rest/services/2021/Cartographic_boundary_files/MapServer/9/query"
    STATCAN_CSD_FR = "https://geo.statcan.gc.ca/geo_wa/rest/services/2021/Fichiers_des_limites_cartographiques/MapServer/9/query"
    OPEN_DATA_CATALOGUE = "https://open.canada.ca/data/en/dataset/b6567c5c-8339-4055-99fa-63f92114d9e4"
    STATCAN_CATALOGUE = "https://open.canada.ca/data/en/dataset/ef70dc3b-1069-4037-9bce-61f47e628a1d"

    attr_reader :manifest_path

    def initialize(release_version:, output_root: DEFAULT_OUTPUT_ROOT, previous_manifest_path: nil,
      http_client: nil, retrieved_at: Time.current, workers: 4, limit: nil)
      @release_version = Date.iso8601(release_version).iso8601
      @output_root = Pathname(output_root).expand_path
      @previous_manifest_path = previous_manifest_path && Pathname(previous_manifest_path)
      @http = http_client || HttpClient.new
      @retrieved_at = retrieved_at.utc
      @workers = Integer(workers)
      @limit = limit && Integer(limit)
      raise ArgumentError, "workers must be positive" unless @workers.positive?
      raise ArgumentError, "limit must be positive" if @limit && !@limit.positive?
    end

    def call
      target = @output_root.join("releases", @release_version)
      raise SourceError, "release source directory already exists: #{target}" if target.exist?

      temporary = @output_root.join(".#{@release_version}-#{SecureRandom.hex(6)}.tmp")
      temporary.mkpath
      begin
        english = fetch_location_features(ISC_LOCATION_EN, temporary.join("isc-location-en.json"))
        french = fetch_location_features(ISC_LOCATION_FR, temporary.join("isc-location-fr.json"))
        validate_language_sets!(english, french)
        english = english.sort_by { |row| Integer(row.fetch("BAND_NUMBER")) }
        source_band_count = english.length
        canonical_ids = allocate_canonical_ids(english)
        english = english.first(@limit) if @limit
        french_by_number = french.index_by { |row| row.fetch("BAND_NUMBER").to_s }

        bands = parallel_map(english) do |row|
          build_band(row, french_by_number.fetch(row.fetch("BAND_NUMBER").to_s), canonical_ids, temporary)
        end.sort_by { |row| Integer(row.fetch(:band_number)) }
        validate_parent_forest!(bands) unless @limit

        payload = build_manifest(bands, source_band_count)
        temporary.join("manifest.json").write(JSON.pretty_generate(payload) << "\n")
        target.dirname.mkpath
        FileUtils.mv(temporary, target)
        @manifest_path = target.join("manifest.json")
      rescue StandardError
        FileUtils.rm_rf(temporary) if temporary.exist?
        raise
      end

      @manifest_path
    end

    private

    def fetch_location_features(endpoint, raw_path)
      features = []
      offset = 0
      pages = []
      loop do
        page = get_json(endpoint, {
          "where" => "1=1", "outFields" => "*", "returnGeometry" => "false",
          "orderByFields" => "BAND_NUMBER", "resultOffset" => offset,
          "resultRecordCount" => 2_000, "f" => "json"
        })
        raise SourceError, "ArcGIS source returned an error: #{page.fetch('error')}" if page["error"]

        rows = Array(page["features"]).map { |feature| feature.fetch("attributes") }
        pages << page
        features.concat(rows)
        break if rows.empty? || !page["exceededTransferLimit"]

        offset += rows.length
      end
      raw_path.write(JSON.pretty_generate({ pages: pages }) << "\n")
      features
    end

    def validate_language_sets!(english, french)
      en = english.map { |row| row.fetch("BAND_NUMBER").to_s }.sort
      fr = french.map { |row| row.fetch("BAND_NUMBER").to_s }.sort
      raise SourceError, "ISC English and French band-number sets differ" unless en == fr
      raise SourceError, "ISC location source returned no bands" if en.empty?
      raise SourceError, "ISC location source contains duplicate band numbers" unless en.uniq.length == en.length
    end

    def allocate_canonical_ids(rows)
      previous = previous_canonical_ids
      claimed = previous.values.to_set
      new_rows = rows.reject { |row| previous.key?(row.fetch("BAND_NUMBER").to_s) }
      bases = new_rows.group_by { |row| slugify(row.fetch("BAND_NAME")) }

      new_rows.each do |row|
        band_number = row.fetch("BAND_NUMBER").to_s
        base = "ca/fn/#{slugify(row.fetch('BAND_NAME'))}"
        candidate = if bases.fetch(base.delete_prefix("ca/fn/")).length > 1 || claimed.include?(base)
          "#{base}-band-#{band_number}"
        else
          base
        end
        candidate = "#{base}-band-#{band_number}" if claimed.include?(candidate)
        raise SourceError, "canonical ID collision for band #{band_number}" if claimed.include?(candidate)

        previous[band_number] = candidate
        claimed << candidate
      end
      previous
    end

    def previous_canonical_ids
      return {} unless @previous_manifest_path

      payload = JSON.parse(@previous_manifest_path.read)
      Array(payload.fetch("bands")).to_h do |row|
        [ row.fetch("band_number").to_s, row.fetch("canonical_id") ]
      end.tap do |mapping|
        raise SourceError, "previous manifest maps multiple bands to one canonical ID" unless mapping.values.uniq.length == mapping.length
      end
    rescue Errno::ENOENT, JSON::ParserError, KeyError => error
      raise SourceError, "invalid previous manifest: #{error.message}"
    end

    def slugify(value)
      slug = ActiveSupport::Inflector.transliterate(value.to_s).downcase
        .gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
      raise SourceError, "band name cannot form a semantic slug: #{value.inspect}" if slug.blank?

      slug
    end

    def build_band(en, fr, canonical_ids, directory)
      number = en.fetch("BAND_NUMBER").to_s
      gaps = []
      profile_url = url_for(FNP_PROFILE, "BAND_NUMBER" => number, "lang" => "eng")
      profile_fr_url = url_for(FNP_PROFILE, "BAND_NUMBER" => number, "lang" => "fra")
      fnfta_url = url_for(FNFTA_LIST, "BAND_NUMBER" => number, "lang" => "eng")
      fnfta_fr_url = url_for(FNFTA_LIST, "BAND_NUMBER" => number, "lang" => "fra")

      profile = fetch_html(profile_url, directory.join("profiles", "#{number}-en.html"), gaps, "FNP profile")
      fnfta_en = fetch_html(fnfta_url, directory.join("fnfta", "#{number}-en.html"), gaps, "FNFTA English listing")
      fnfta_fr = fetch_html(fnfta_fr_url, directory.join("fnfta", "#{number}-fr.html"), gaps, "FNFTA French listing")
      reports = parse_fnfta_reports(fnfta_en, fnfta_fr, canonical_ids.fetch(number), fnfta_url, fnfta_fr_url, gaps)
      geography = fetch_statcan_geography(en, gaps, directory)
      profile_data = parse_profile(profile)

      {
        band_number: number,
        canonical_id: canonical_ids.fetch(number),
        name_en: en.fetch("BAND_NAME"),
        name_fr: fr["BAND_NAME"].presence,
        institution_type: "government",
        government_level: "first_nation",
        legal_form: "First Nation band",
        status: "active",
        website_url: profile_data[:website_url],
        contact: profile_data[:contact],
        profile_urls: { en: profile_url, fr: profile_fr_url },
        identifiers: [ {
          scheme: "isc.band_number", value: number, preferred: true,
          source_url: OPEN_DATA_CATALOGUE
        } ],
        parent_band_number: en["PARENT_FIRST_NATION"].presence&.to_s,
        parent_band_name: en["PARENT_FIRST_NATION_NAME"].presence,
        location: {
          latitude: numeric(en["LATITUDE"]), longitude: numeric(en["LONGITUDE"]),
          kind: "isc-administrative-office-point",
          most_populated_reserve_number: en["MOST_POPULATED_RESERVE_NUM"].presence&.to_s,
          most_populated_reserve_name: en["MOST_POPULATED_RESERVE_NAME"].presence
        }.compact,
        statcan_geographies: geography ? [ geography ] : [],
        reports: reports,
        provenance: {
          retrieved_at: @retrieved_at.iso8601,
          location_source_url: OPEN_DATA_CATALOGUE,
          profile_source_url: profile_url,
          fnfta_source_url: fnfta_url
        },
        gaps: gaps
      }
    end

    def fetch_html(url, path, gaps, label)
      body = @http.get(url)
      path.dirname.mkpath
      path.binwrite(body)
      body
    rescue StandardError => error
      gaps << "#{label} unavailable: #{error.message}"
      nil
    end

    def parse_profile(html)
      return { website_url: nil, contact: {} } unless html

      document = Nokogiri::HTML(html)
      link = document.at_css("a#plcMain_anchor1") || document.xpath("//a").find do |anchor|
        anchor.text.squish.match?(/\A(web ?site|site web)\z/i) && anchor["href"].to_s.match?(/\Ahttps?:\/\//)
      end
      fields = {}
      document.xpath("//tr").each do |row|
        cells = row.xpath("./th|./td").map { |cell| cell.text.squish }
        next if cells.length < 2
        key = cells.first.downcase.delete_suffix(":")
        fields[key] = cells.drop(1).join(" ").presence
      end
      {
        website_url: link&.[]("href").to_s.strip.match?(/\Ahttps?:\/\//) ? link["href"].strip : nil,
        contact: {
          phone: field(fields, /phone|téléphone/),
          civic_address: field(fields, /address|adresse/),
          mailing_address: field(fields, /mailing address|adresse postale/)
        }.compact
      }
    end

    def field(fields, pattern)
      fields.find { |key, _value| key.match?(pattern) }&.last
    end

    def parse_fnfta_reports(english_html, french_html, canonical_id, source_url, source_fr_url, gaps)
      english = fnfta_rows(english_html, :en)
      french = fnfta_rows(french_html, :fr).index_by { |row| row.fetch(:fiscal_year_label) }
      missing_links = english.count { |row| row[:download_url].nil? }
      gaps << "#{missing_links} FNFTA audited-statement rows had no downloadable document" if missing_links.positive?

      english.filter_map do |row|
        next unless row[:download_url]
        year_start, year_end = fiscal_years(row.fetch(:fiscal_year_label))
        french_row = french[row.fetch(:fiscal_year_label)]
        {
          canonical_id: "#{canonical_id}/documents/financial-statements/#{year_end}/consolidated",
          document_type: "financial-statements",
          document_variant: "consolidated",
          title_en: row.fetch(:title),
          title_fr: french_row&.fetch(:title),
          fiscal_year_label: row.fetch(:fiscal_year_label),
          fiscal_period_start: Date.new(year_start, 4, 1).iso8601,
          fiscal_period_end: Date.new(year_end, 3, 31).iso8601,
          period_basis: "inferred-from-fnfta-fiscal-year-label",
          date_received: row[:date_received],
          source_page_url: source_url,
          source_page_url_fr: source_fr_url,
          download_url: row.fetch(:download_url),
          rights_status: "metadata_only"
        }.compact
      end.uniq { |row| row.fetch(:canonical_id) }
    end

    def fnfta_rows(html, language)
      return [] unless html

      Nokogiri::HTML(html).xpath("//tr").filter_map do |row|
        cells = row.xpath("./th|./td")
        next if cells.length < 2
        year = cells[0].text.squish
        next unless year.match?(/\A\d{4}-\d{4}\z/)
        anchor = cells[1].at_css("a")
        title = (anchor&.text.presence || cells[1].text).squish
        audited = language == :fr ? title.match?(/états financiers consolidés.*(vérifiés|audités)/i) : title.match?(/audited consolidated financial statements/i)
        next unless audited

        href = anchor&.[]("href").to_s.strip
        {
          fiscal_year_label: year,
          title: title,
          date_received: cells[2]&.text&.squish&.presence,
          download_url: href.blank? || href == "#" ? nil : URI.join(FNFTA_LIST, URI::DEFAULT_PARSER.escape(href)).to_s
        }
      end
    end

    def fiscal_years(label)
      start_year, end_year = label.split("-").map { |year| Integer(year) }
      raise SourceError, "invalid FNFTA fiscal year #{label}" unless end_year == start_year + 1

      [ start_year, end_year ]
    end

    def fetch_statcan_geography(row, gaps, directory)
      latitude = numeric(row["LATITUDE"])
      longitude = numeric(row["LONGITUDE"])
      unless latitude && longitude
        gaps << "ISC location has no usable coordinates; StatsCan CSD was not associated"
        return nil
      end
      common = {
        "where" => "1=1", "geometry" => "#{longitude},#{latitude}",
        "geometryType" => "esriGeometryPoint", "inSR" => 4326,
        "spatialRel" => "esriSpatialRelIntersects", "returnGeometry" => "false", "f" => "json"
      }
      en_response = get_json(STATCAN_CSD_EN, common.merge("outFields" => "CSDUID,DGUID,CSDNAME,CSDTYPE,PRUID"))
      fr_response = get_json(STATCAN_CSD_FR, common.merge("outFields" => "SDRIDU,IDUGD,SDRNOM,SDRGENRE,PRIDU"))
      statcan_path = directory.join("statcan-csd", "#{row.fetch('BAND_NUMBER')}.json")
      statcan_path.dirname.mkpath
      statcan_path.write(JSON.pretty_generate({ en: en_response, fr: fr_response }) << "\n")
      en = Array(en_response["features"])
      fr = Array(fr_response["features"])
      if en.empty?
        gaps << "ISC location point did not intersect a 2021 StatsCan CSD"
        return nil
      end
      raise SourceError, "ISC location point intersects multiple StatsCan CSDs" unless en.one?

      en = en.first.fetch("attributes")
      fr = fr.first&.fetch("attributes", {}) || {}
      {
        uid: en.fetch("CSDUID").to_s,
        dguid: en["DGUID"].presence,
        name_en: en.fetch("CSDNAME"), name_fr: fr["SDRNOM"].presence,
        boundary_type: "csd", type_en: en["CSDTYPE"], type_fr: fr["SDRGENRE"],
        province_code: en["PRUID"].to_s.rjust(2, "0"), vintage: 2021,
        role: "headquartered_in", source_url: STATCAN_CATALOGUE
      }.compact
    rescue StandardError => error
      gaps << "StatsCan CSD lookup unavailable: #{error.message}"
      nil
    end

    def validate_parent_forest!(bands)
      numbers = bands.to_h { |row| [ row.fetch(:band_number), row ] }
      bands.each do |row|
        parent = row[:parent_band_number]
        next if parent.blank?
        raise SourceError, "band #{row.fetch(:band_number)} has unknown parent band #{parent}" unless numbers.key?(parent)

        seen = Set.new
        current = row.fetch(:band_number)
        while current
          raise SourceError, "ISC parent First Nation fields contain a cycle" if seen.include?(current)
          seen << current
          current = numbers.fetch(current)[:parent_band_number]
        end
      end
    end

    def numeric(value)
      return nil if value.nil?
      number = Float(value)
      number.finite? ? number : nil
    rescue ArgumentError, TypeError
      nil
    end

    def build_manifest(bands, source_count)
      {
        product: "canadian-public-institutions-first-nations",
        release_version: @release_version,
        effective_on: @release_version,
        schema_version: "1.0",
        geography_vintage: 2021,
        retrieved_at: @retrieved_at.iso8601,
        scope: @limit ? "partial" : "national",
        source_band_count: source_count,
        attribution: "Indigenous Services Canada; Crown-Indigenous Relations and Northern Affairs Canada; Statistics Canada",
        sources: source_inventory,
        bands: bands
      }
    end

    def source_inventory
      [
        { key: "isc_location", publisher: "Indigenous Services Canada", title_en: "First Nations Location",
          url: OPEN_DATA_CATALOGUE, endpoint_en: ISC_LOCATION_EN, endpoint_fr: ISC_LOCATION_FR,
          languages: %w[en fr], license: "Open Government Licence - Canada", update_frequency: "daily" },
        { key: "fnp", publisher: "Indigenous Services Canada", title_en: "First Nation Profiles",
          url: FNP_PROFILE, languages: %w[en fr], access: "legacy ASP.NET HTML; direct band-number GET" },
        { key: "fnfta", publisher: "Indigenous Services Canada", title_en: "First Nations Financial Transparency Act documents",
          url: FNFTA_LIST, languages: %w[en fr], access: "legacy ASP.NET HTML; some listed rows have no binary link" },
        { key: "statcan_csd_2021", publisher: "Statistics Canada", title_en: "2021 Census subdivision cartographic boundaries",
          url: STATCAN_CATALOGUE, endpoint_en: STATCAN_CSD_EN, endpoint_fr: STATCAN_CSD_FR,
          languages: %w[en fr], license: "Statistics Canada Open Licence" }
      ]
    end

    def get_json(url, params)
      JSON.parse(@http.get(url, params: params))
    rescue JSON::ParserError => error
      raise SourceError, "invalid JSON from #{url}: #{error.message}"
    end

    def url_for(url, params)
      uri = URI(url)
      uri.query = URI.encode_www_form(params)
      uri.to_s
    end

    def parallel_map(rows)
      queue = Queue.new
      rows.each_with_index { |row, index| queue << [ index, row ] }
      results = Array.new(rows.length)
      errors = Queue.new
      [ @workers, rows.length ].min.times.map do
        Thread.new do
          loop do
            index, row = queue.pop(true)
            results[index] = yield(row)
          rescue ThreadError
            break
          rescue StandardError => error
            errors << error
            break
          end
        end
      end.each(&:join)
      raise errors.pop unless errors.empty?

      results
    end

    class HttpClient
      USER_AGENT = "YorkFactory-PublicInstitutionOntology/1.0 (+https://buildcanada.com)"

      def get(url, params: nil, redirects: 5)
        uri = URI(url)
        uri.query = URI.encode_www_form(params) if params
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = USER_AGENT
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
          open_timeout: 20, read_timeout: 90) { |http| http.request(request) }
        return response.body if response.is_a?(Net::HTTPSuccess)
        if response.is_a?(Net::HTTPRedirection) && redirects.positive?
          return get(URI.join(uri, response.fetch("location")).to_s, redirects: redirects - 1)
        end

        raise SourceError, "HTTP #{response.code} for #{uri}"
      end
    end
  end
end
