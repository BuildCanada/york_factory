module PublicApi
  # Resolves `as_of` (the AsOf parameter) to a registry revision: a revision
  # number pins that revision; a snapshot name pins the revision it names; an
  # RFC 3339 timestamp or a date (read as 00:00 UTC) resolves to the newest
  # served revision committed at or before it; omitted means the latest served
  # revision (the newest the derived tables are built at). A revision before
  # the earliest committed one, or committed after the latest served one, is
  # 404 not_yet_published.
  #
  # `pinned` says whether the answer can never change, which decides
  # Cache-Control: a number or a snapshot name always, a time only once it has
  # passed (a later revision can't commit in the past).
  class AsOf
    Resolved = Data.define(:revision, :snapshot, :pinned, :requested) do
      def to_s = revision.to_s
    end

    SNAPSHOT = /\A[a-z][a-z0-9._-]*\z/

    def self.resolve(value, served:, now: Time.current) = new(served:, now:).resolve(value)

    def initialize(served:, now: Time.current)
      @served = served
      @now = now
    end

    def resolve(value)
      if @served.empty?
        raise Problem.new(:revision_building, "No registry revision is served yet: the first derived build has not finished. Retry shortly.",
          headers: { "Retry-After" => "30" }, retry_after_seconds: 30)
      end
      return resolved(@served.latest, pinned: false, requested: nil) if value.blank?

      value = value.to_s
      if value.match?(/\A\d+\z/) then by_number(value.to_i, value)
      elsif value.match?(SNAPSHOT) then by_snapshot(value)
      else by_time(value)
      end
    end

    private

    def resolved(revision, pinned:, requested:, snapshot: nil)
      Resolved.new(revision:, snapshot: snapshot || @served.snapshot_for(revision), pinned:, requested:)
    end

    def by_number(number, value)
      raise not_yet_published("as_of #{value} is before revision #{@served.earliest}, the earliest committed.") if number < @served.earliest
      raise not_yet_published("Revision #{number} isn't served yet: the API serves up to revision #{@served.latest}.") if number > @served.latest
      raise Problem.not_found("Revision #{number} was not committed.") unless @served.committed?(number)

      resolved(number, pinned: true, requested: value)
    end

    def by_snapshot(name)
      revision = @served.snapshots[name] or raise Problem.not_found("No snapshot named #{name}. GET /v1/snapshots lists them.")
      raise not_yet_published("Snapshot #{name} pins revision #{revision}, which isn't served yet.") if revision > @served.latest

      resolved(revision, pinned: true, requested: name, snapshot: name)
    end

    def by_time(value)
      time = parse_time(value)
      revision = @served.at(time)
      raise not_yet_published("as_of #{value} is before revision #{@served.earliest}, the earliest committed.") unless revision

      resolved(revision, pinned: time <= @now, requested: value)
    end

    def parse_time(value)
      value.include?("T") ? Time.iso8601(value) : Date.iso8601(value).in_time_zone("UTC")
    rescue ArgumentError
      raise Problem.invalid(parameter: "as_of", detail: Parameters::HINTS.fetch("as_of"))
    end

    def not_yet_published(detail)
      Problem.new(:not_yet_published, detail, earliest_revision: @served.earliest, latest_revision: @served.latest)
    end
  end
end
