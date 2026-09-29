module FactFactory
  # Releases the read model serves (api.releases). The list of release numbers
  # is small and changes only when fact-factory publishes, so it is kept in
  # process for POINTER_TTL (the edge caches its latest-release pointer for
  # the same 30 s, docs/public-interface-design.md §5.5).
  class ReleaseQuery
    POINTER_TTL = Rails.env.test? ? 0 : 30

    class << self
      def served
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if @served.nil? || now - @served_at >= POINTER_TTL
          @served = Release.order(:release_id).pluck(:release_id, :published_at).map do |number, published_at|
            PublicApi::AsOf::ServedRelease.new(number:, published_at:)
          end
          @served_at = now
        end
        @served
      end

      def reset!
        @served = nil
        @snapshots = nil
        @counts = nil
      end

      def find(number) = Release.find_by(release_id: number)

      # Newest first, after the release `before` (a cursor key), or from the top.
      def page(limit:, before: nil)
        scope = Release.order(release_id: :desc).limit(limit + 1)
        scope = scope.where("release_id < ?", before) if before
        scope.to_a
      end

      def count = Release.count

      # The pinned Iceberg snapshot of each spending slice, keyed by the
      # occurrence label (`<asset_key>` or `<asset_key>@archive_import`).
      def spending_snapshots(number)
        @snapshots ||= {}
        @snapshots[number] ||= (find(number)&.spending_snapshots || {})
      end

      def snapshot_for(number, asset_key:, acquisition:)
        label = acquisition == "live" ? asset_key : "#{asset_key}@#{acquisition}"
        spending_snapshots(number).dig(label, "snapshot_id")
      end

      # Rows per table in a release. api.releases.counts records what each
      # build added and closed, not totals, so the totals are the running sum
      # over every served release up to this one (spending records are the
      # pinned snapshots' row counts). Immutable per release, so memoized.
      def counts(number)
        @counts ||= {}
        @counts[number] ||= begin
          totals = Hash.new(0)
          Release.where("release_id <= ?", number).order(:release_id).pluck(:counts).each do |counts|
            %w[entities identifiers relationships spending_parties entity_names].each do |table|
              step = counts[table]
              totals[table] += step.to_i if step.is_a?(Integer)
              totals[table] += step.fetch("added", 0).to_i - step.fetch("closed", 0).to_i if step.is_a?(Hash)
            end
          end
          release = find(number)
          totals["spending_records"] = (release&.spending_snapshots || {}).values.sum { |s| s["rows"].to_i }
          totals["spending_summary"] = release&.counts&.dig("spending_summary").to_i
          totals.delete("entity_names")
          totals.transform_values { |v| [ v, 0 ].max }
        end
      end
    end
  end
end
