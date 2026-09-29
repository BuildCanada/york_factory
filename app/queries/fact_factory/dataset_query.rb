module FactFactory
  # Release facts about datasets: row counts, fiscal-year coverage and bulk
  # files (api.release_exports). Immutable per release, so memoized.
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

    # [first fiscal year, last fiscal year] of a spending asset's rows in the
    # release. Two ordered probes of the (asset_key, fiscal_year) index, not a
    # scan of the table.
    def fiscal_years(asset_key)
      self.class.memo(:fiscal_years, release, asset_key) do
        %w[ASC DESC].map do |direction|
          sql = "SELECT r.fiscal_year FROM api.spending_records r WHERE r.asset_key = :asset AND r.fiscal_year IS NOT NULL " \
            "AND #{FactFactoryRecord.in_release('r')} ORDER BY r.fiscal_year #{direction} LIMIT 1"
          SpendingRecord.connection.select_value(SpendingRecord.sanitize_sql_array([ sql, { asset: asset_key, n: release } ]))&.to_i
        end
      end
    end

    # Rows of each spending asset in the release: the pinned snapshots' rows.
    def spending_rows(asset_key)
      ReleaseQuery.spending_snapshots(release).sum do |label, state|
        label.split("@").first == asset_key ? state["rows"].to_i : 0
      end
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
