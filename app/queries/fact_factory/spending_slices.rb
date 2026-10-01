module FactFactory
  # The spending rows registry revision N reads. fact-factory resolves spending
  # one slice at a time (a source and acquisition, labelled by its asset key, with
  # `@archive_import` for archive copies): a revision that resolved a slice
  # records the slice's spending version in `registry_revisions.inputs.slices`.
  # As of N, a slice stands at the version the newest committed revision at or
  # before N recorded for it (fact-factory's revisions.slice_inputs), and its rows
  # are those of the publications committed at or before that version and not yet
  # replaced (spending_store.VISIBLE). Those are the rows N's spending
  # occurrences and summaries were resolved from, so the API serves exactly them.
  #
  # A slice fact-factory has not resolved since spending moved to PostgreSQL holds
  # an Iceberg snapshot ID, not a version; a version whose replaced rows were
  # purged can't be read either. Such slices are left out and named in
  # `unreadable` (the coverage_partial caveat).
  class SpendingSlices
    Slice = Data.define(:label, :asset_key, :source_key, :acquisition, :version, :publications)

    attr_reader :revision, :slices, :unreadable

    def self.load(revision) = new(revision).tap(&:load!)

    def initialize(revision)
      @revision = revision
      @slices = {}
      @unreadable = {}
    end

    def load!
      inputs = Revision.connection.select_rows(Revision.sanitize_sql_array([ <<~SQL, { n: revision } ]))
        SELECT DISTINCT ON (s.key) s.key, s.value
        FROM #{FactFactoryRecord.table('registry_revisions')} r
        CROSS JOIN LATERAL json_each_text(r.inputs -> 'slices') s
        WHERE r.state = 'committed' AND r.id <= :n AND json_typeof(r.inputs -> 'slices') = 'object'
        ORDER BY s.key, r.id DESC
      SQL
      newest = SpendingPublication.maximum(:version).to_i
      inputs.each do |label, value|
        asset_key, acquisition = label.split("@", 2)
        acquisition ||= "live"
        source = PublicApi::Catalog.source_for_asset(asset_key) or next
        version = value.to_s.match?(/\A\d+\z/) ? value.to_i : nil
        if version.nil? || version > newest
          @unreadable[label] = "resolved at #{value}, a snapshot from before spending moved to PostgreSQL"
          next
        end
        publications = SpendingPublication.where(source_key: source.key, acquisition:)
          .where("version IS NOT NULL AND version <= :v AND (replaced_version IS NULL OR replaced_version > :v)", v: version)
          .order(:id).to_a
        if publications.any?(&:purged_at)
          @unreadable[label] = "its version #{version} needs replaced publications whose rows were purged"
          next
        end
        @slices[label] = Slice.new(label:, asset_key:, source_key: source.key, acquisition:, version:, publications:)
      end
      self
    end

    def publications = @publications ||= slices.values.flat_map(&:publications).index_by(&:id)

    def publication_ids = publications.keys

    def publication(id) = publications[id]

    def slice_for(source_key, acquisition) = slices.values.find { |s| s.source_key == source_key && s.acquisition == acquisition }

    def live(source_key) = slice_for(source_key, "live")

    def empty? = publications.empty?
  end
end
