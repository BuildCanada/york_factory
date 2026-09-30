module FactFactory
  # Release facts about datasets: which datasets a release serves, their rows
  # and fiscal-year coverage (api.datasets), and bulk files
  # (api.release_exports). Immutable per release, so memoized.
  class DatasetQuery
    FILES_BASE = "https://files.buildcanada.com".freeze
    # The api table each registry export is (fact-factory serve/exports.py),
    # named for the bulk file as <namespace>.<table>.
    EXPORT_TABLES = {
      "entities" => "entities.entities",
      "identifiers" => "entities.identifiers",
      "relationships" => "entities.relationships",
      "spending_parties" => "entities.spending_parties"
    }.freeze

    class << self
      def reset! = @memo = nil

      def memo(*key)
        @memo ||= {}
        @memo.fetch(key) { @memo[key] = yield }
      end
    end

    attr_reader :release

    def initialize(release:)
      @release = release
    end

    # {asset_key => [Dataset]}: the slices of each dataset the release serves
    # (a spending table's live and archive_import slices, or one registry
    # table).
    def served
      self.class.memo(:served, release) { Dataset.where(release_id: release).order(:asset_key, :acquisition).to_a.group_by(&:asset_key) }
    end

    def served?(asset_key) = served.key?(asset_key)

    # Rows of a dataset in the release, over its slices.
    def rows(asset_key) = served.fetch(asset_key, []).sum { |d| d.rows.to_i }

    # [first fiscal year, last fiscal year] of a spending dataset's served
    # rows, over its slices.
    def fiscal_years(asset_key)
      slices = served.fetch(asset_key, [])
      [ slices.filter_map(&:fiscal_year_min).min, slices.filter_map(&:fiscal_year_max).max ]
    end

    # The release's Parquet files (not its manifest), optionally one table's.
    def exports(table: nil)
      self.class.memo(:exports, release) do
        ReleaseExport.where(release_id: release).where.not(table_name: "manifest.json").order(:table_name).to_a
      end.select { |e| table.nil? || export_table(e) == table }
    end

    def export_table(export) = EXPORT_TABLES.fetch(export.table_name, export.table_name)

    def export_url(export) = export.url.presence || "#{FILES_BASE}/#{export.object_key}"
  end
end
