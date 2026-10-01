module FactFactory
  # Facts about datasets as of one registry revision: which spending sources the
  # revision reads and their rows and freshness (the publications of its
  # slices), and the registry tables' row counts. Immutable per revision, so
  # memoized.
  class DatasetQuery
    # The fact-factory table each registry dataset (datasets.yml `table`) is.
    # mention_occurrences is counted in no request: about 12M rows.
    REGISTRY_TABLES = {
      "entities" => "entities",
      "identifiers" => "entity_identifiers",
      "relationships" => "entity_relationships",
      "spending_parties" => nil
    }.freeze

    class << self
      def reset! = @memo = nil

      def memo(*key)
        @memo ||= {}
        @memo.fetch(key) { @memo[key] = yield }
      end
    end

    attr_reader :revision

    def initialize(revision:)
      @revision = revision
    end

    def slices = RevisionQuery.slices(revision)

    def publications(asset_key) = slices.slices.values.select { |s| s.asset_key == asset_key }.flat_map(&:publications)

    # A spending source is served when the revision reads any of its slices.
    def served?(asset_key) = publications(asset_key).any?

    # Rows of a spending dataset as of the revision, over its slices.
    def spending_rows(asset_key) = publications(asset_key).sum { |p| p.row_count.to_i }

    # When the newest capture the revision reads for the dataset was retrieved.
    def latest_retrieved_at(asset_key)
      at = publications(asset_key).filter_map(&:observed_at).max
      at && Time.at(at).utc
    end

    # Rows of a registry table as of the revision, or nil when not counted.
    def registry_rows(table)
      name = REGISTRY_TABLES.fetch(table, nil) or return nil

      self.class.memo(:rows, revision, name) do
        Entity.connection.select_value(Entity.sanitize_sql_array([
          "SELECT count(*) FROM #{FactFactoryRecord.table(name)} t WHERE #{FactFactoryRecord.as_of('t')}", { n: revision }
        ])).to_i
      end
    end
  end
end
