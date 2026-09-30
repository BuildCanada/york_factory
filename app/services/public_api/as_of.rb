module PublicApi
  # Resolves `as_of` (the AsOf parameter): a release number pins that release;
  # an RFC 3339 timestamp or a date (read as 00:00 UTC) resolves to the release
  # current then; omitted means the latest. A value before the first served
  # release is 404 not_yet_published.
  #
  # `pinned` says whether the answer can never change, which decides the
  # Cache-Control header: a release number always, a time only once it has
  # passed (a later release can't be published in the past).
  class AsOf
    Resolved = Data.define(:release, :pinned, :requested) do
      def to_s = release.to_s
    end

    ServedRelease = Data.define(:number, :published_at)

    def self.resolve(value, releases:, now: Time.current) = new(releases:, now:).resolve(value)

    def initialize(releases:, now: Time.current)
      @releases = releases.sort_by(&:number)
      @now = now
    end

    def resolve(value)
      raise Problem.new(:release_building, "No release is published yet. Retry shortly.", headers: { "Retry-After" => "30" }, retry_after_seconds: 30) if @releases.empty?
      return Resolved.new(release: latest.number, pinned: false, requested: nil) if value.blank?

      value.to_s.match?(/\A\d+\z/) ? by_number(value.to_i, value) : by_time(value)
    end

    def latest = @releases.last

    def earliest = @releases.first

    private

    def by_number(number, value)
      if number < earliest.number
        raise not_yet_published("as_of #{value} is before release #{earliest.number}, the earliest the API serves.")
      end
      unless @releases.any? { |r| r.number == number }
        raise Problem.not_found("Release #{number} is not published. The latest is #{latest.number}.")
      end

      Resolved.new(release: number, pinned: true, requested: value)
    end

    def by_time(value)
      time = parse_time(value)
      release = @releases.select { |r| r.published_at <= time }.last
      unless release
        raise not_yet_published("as_of #{value} is before release #{earliest.number}, published #{earliest.published_at.to_date.iso8601}.")
      end

      Resolved.new(release: release.number, pinned: time <= @now, requested: value)
    end

    def parse_time(value)
      value.include?("T") ? Time.iso8601(value) : Date.iso8601(value).in_time_zone("UTC")
    rescue ArgumentError
      raise Problem.invalid(parameter: "as_of", detail: "Use a release number (11), a date (2026-09-01) or an RFC 3339 timestamp (2026-09-01T00:00:00Z).")
    end

    def not_yet_published(detail)
      Problem.new(:not_yet_published, detail, earliest_release: earliest.number)
    end
  end
end
