require "csv"
require "digest"
require "open3"

class Warehouse::CensusProfileImporter
  SOURCE_URL = "https://www12.statcan.gc.ca/census-recensement/2021/dp-pd/prof/details/download-telecharger/comp/getFile.cfm?LANG=E&GEONO=005&FILETYPE=CSV"
  CSV_ENTRY = "98-401-X2021005_English_CSV_data.csv"

  class ImportError < StandardError; end

  def initialize(zip_path:, expected_sha256:, retrieved_at:)
    @zip_path = Pathname(zip_path).expand_path
    @expected_sha256 = expected_sha256
    @retrieved_at = retrieved_at.to_time
  end

  def import!
    validate_source!
    profiles = read_profiles
    now = Time.current
    rows = profiles.map do |uid, values|
      {
        census_year: 2021, geo_level: "csd", geo_uid: uid,
        population: values.fetch(:population), area_sq_km: values[:area_sq_km],
        population_density_per_sq_km: values[:population_density_per_sq_km],
        source_url: SOURCE_URL, source_sha256: @expected_sha256,
        retrieved_at: @retrieved_at, created_at: now, updated_at: now
      }
    end
    Warehouse::CensusProfile.insert_all(
      rows, unique_by: "index_census_profiles_vintage_geography_source"
    )
    {
      source_url: SOURCE_URL,
      source_sha256: @expected_sha256,
      census_profile_rows: profiles.length,
      stored_profiles: Warehouse::CensusProfile.where(
        census_year: 2021, geo_level: "csd", source_sha256: @expected_sha256
      ).count
    }
  end

  private

  def validate_source!
    raise ImportError, "missing Census Profile archive #{@zip_path}" unless @zip_path.file?
    actual = Digest::SHA256.file(@zip_path).hexdigest
    raise ImportError, "Census Profile SHA-256 mismatch: expected #{@expected_sha256}, got #{actual}" unless actual == @expected_sha256
  end

  def read_profiles
    rows = Hash.new { |hash, uid| hash[uid] = {} }
    Open3.popen3("unzip", "-p", @zip_path.to_s, CSV_ENTRY) do |stdin, stdout, stderr, wait|
      stdin.close
      stdout.set_encoding(Encoding::Windows_1252, Encoding::UTF_8, invalid: :replace, undef: :replace)
      headers = CSV.parse_line(stdout.gets)
      indexes = %w[DGUID GEO_LEVEL CHARACTERISTIC_ID C1_COUNT_TOTAL]
        .to_h { |name| [ name, headers.index(name) || raise(ImportError, "missing Census Profile column #{name}") ] }
      stdout.each_line do |line|
        next unless line.include?("Census subdivision")
        next unless line.match?(/,(?:1|6|7),"(?:Population, 2021|Population density per square kilometre|Land area in square kilometres)",/)

        values = CSV.parse_line(line)
        next unless values[indexes.fetch("GEO_LEVEL")] == "Census subdivision"

        uid = values[indexes.fetch("DGUID")].to_s.delete_prefix("2021A0005")
        next unless uid.length == 7

        value = values[indexes.fetch("C1_COUNT_TOTAL")]
        case values[indexes.fetch("CHARACTERISTIC_ID")]
        when "1"
          population = Integer(value, exception: false)
          rows[uid][:population] = population if population&.positive?
        when "6"
          density = BigDecimal(value, exception: false)
          rows[uid][:population_density_per_sq_km] = density if density && density >= 0
        when "7"
          area = BigDecimal(value, exception: false)
          rows[uid][:area_sq_km] = area if area&.positive?
        end
      end
      error = stderr.read
      raise ImportError, "unzip failed: #{error}" unless wait.value.success?
    end
    rows.select! { |_uid, values| values[:population]&.positive? }
    raise ImportError, "Census Profile contained no CSD profile rows" if rows.empty?

    rows
  rescue CSV::MalformedCSVError => error
    raise ImportError, "invalid Census Profile CSV: #{error.message}"
  end
end
