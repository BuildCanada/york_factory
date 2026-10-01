module FactFactory
  # Registry revisions, the API's version unit (docs/public-interface-design.md
  # §3.1, D7): fact-factory's registry commits a revision whenever an input
  # changes, and `registry_snapshots` names some of them (`release-14`, held for
  # the gold set). The API serves every committed revision up to the newest one
  # its derived tables are built at (`derived_builds`): those are the revisions
  # whose names and spending summaries exist.
  #
  # The list of committed revisions changes only when fact-factory commits, so it
  # is kept in process for POINTER_TTL (the edge caches its latest pointer for the
  # same 30 s, §5.5). What a committed revision read never changes, so its spending
  # slices are memoized for good.
  class RevisionQuery
    POINTER_TTL = Rails.env.test? ? 0 : 30

    # The revisions the API can answer for: `numbers` (committed, ascending, up
    # to `latest`), when each committed, which retention pruned, and the
    # snapshots' names.
    Served = Data.define(:latest, :committed, :pruned, :snapshots, :purged_through) do
      def empty? = latest.nil?

      def earliest = committed.keys.first

      def committed?(number) = committed.key?(number) && number <= latest

      def committed_at(number) = committed[number]

      def pruned?(number) = pruned.include?(number)

      # The newest served revision committed at or before `time`.
      def at(time)
        committed.select { |number, at| number <= latest && at && at <= time }.keys.last
      end

      # Whether a revision committed at or before `time` is still waiting for its
      # derived build: until it is served, `at(time)` answers with an earlier one.
      def building_by?(time) = committed.any? { |number, at| number > latest && at && at <= time }

      # The first snapshot name pinning a revision, for meta.snapshot and cites.
      def snapshot_for(number) = snapshots.select { |_, revision| revision == number }.keys.min
    end

    class << self
      def served
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if @served.nil? || now - @served_at >= POINTER_TTL
          @served = load_served
          @served_at = now
        end
        @served
      end

      def reset!
        @served = nil
        @slices = nil
      end

      def load_served
        latest = DerivedBuild.maximum(:revision_id)
        rows = Revision.where(state: "committed").order(:id).pluck(:id, :committed_at, :pruned_at)
        committed = rows.to_h { |id, at, _| [ id, at && Time.at(at).utc ] }
        pruned = rows.filter_map { |id, _, pruned_at| id if pruned_at }.to_set
        snapshots = Snapshot.pluck(:name, :revision_id).to_h
        purged_through = SpendingPublication.maximum(:purged_at)
        Served.new(latest:, committed:, pruned:, snapshots:, purged_through:)
      end

      def find(number) = Revision.find_by(id: number, state: "committed")

      def build(number) = DerivedBuild.find_by(revision_id: number)

      # Committed revisions, newest first, before the cursor's `before`.
      def page(limit:, before: nil)
        scope = Revision.where(state: "committed").order(id: :desc).limit(limit + 1)
        scope = scope.where("id < ?", before) if before
        scope.to_a
      end

      def snapshot(name) = Snapshot.find_by(name:)

      def snapshots_page(limit:, after: nil)
        scope = Snapshot.order(created_at: :desc, name: :asc).limit(limit + 1)
        if after
          scope = scope.where("created_at < :at OR (created_at = :at AND name > :name)", at: after[0].to_f, name: after[1])
        end
        scope.to_a
      end

      # The spending rows revision N reads (SpendingSlices). Memoized until a
      # publication is purged: a committed revision's inputs never change, but a
      # purge makes a slice that needed the purged rows unreadable.
      def slices(number)
        purged = served.purged_through
        @slices = {} if @slices.nil? || @slices_purged != purged
        @slices_purged = purged
        @slices[number] ||= SpendingSlices.load(number)
      end
    end
  end
end
