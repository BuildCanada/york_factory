# Resolves a postal code to the boundary containing it — a municipal ward
# today, a school board ward or any other loaded boundary type on request.
#
# Deliberately not keyed to a city. Wards are stored in warehouse.geo_boundaries
# like every other boundary type, so the same query answers Toronto, Ottawa or
# Vancouver as soon as their ward layer is loaded; nothing here needs to change.
#
# HOW EXACT THIS IS: a postal code's stored point is the centroid of its
# delivery points, so a code straddling a ward line can resolve to the
# neighbour. Warehouse::Election::PledgeEligibility measures that at 0.08%–0.9%
# of a city's codes against *municipal* lines; ward lines are far more numerous,
# so the rate here is higher. Callers should present the result as a best guess
# ("looks like Ward 19") with a way to browse the rest, never as a hard fact.
#
# The reasons mirror PledgeEligibility's split between "we could not judge" and
# "we judged you outside" (see #indeterminate?), because the two want different
# copy: one asks the reader to check what they typed, the other tells them they
# are outside the city.
class Warehouse::BoundaryLookup
  DEFAULT_BOUNDARY_TYPE = "ward".freeze

  REASONS = %i[
    resolved malformed_postal_code unknown_postal_code
    outside_boundary boundary_data_unavailable
  ].freeze

  Result = Data.define(:found, :reason, :postal_code, :city, :boundary) do
    def found? = found

    # True where we could not judge, as opposed to judging the point outside a
    # boundary we do hold. `boundary_data_unavailable` belongs here and is on
    # us, not the reader: it means no boundaries of this type are loaded.
    def indeterminate?
      %i[malformed_postal_code unknown_postal_code boundary_data_unavailable].include?(reason)
    end
  end

  attr_reader :boundary_type

  def initialize(boundary_type: DEFAULT_BOUNDARY_TYPE)
    @boundary_type = boundary_type
  end

  def check(raw_postal_code)
    normalized = Warehouse::PostalCode.normalize(raw_postal_code)
    return miss(:malformed_postal_code) if normalized.nil?

    record = Warehouse::PostalCode.find_by(postal_code: normalized)
    return miss(:unknown_postal_code, normalized) if record.nil?

    boundary = containing_boundary(record)
    return found(normalized, record.city, boundary) if boundary

    # Nothing contained the point. Whether that means the reader is outside the
    # city or that we never loaded the layer is the difference between their
    # problem and ours, so say which.
    return miss(:boundary_data_unavailable, normalized, record.city) unless boundaries_loaded?

    miss(:outside_boundary, normalized, record.city)
  end

  private

  # Ordering by census_year descending matters once a post-2026 ward model
  # lands beside the current one. A point on a shared edge can match two
  # boundaries of the same vintage; taking the first is fine given the
  # accuracy note above.
  def containing_boundary(record)
    scope
      .where(
        "ST_Intersects(geometry, ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)::geography)",
        lon: record.longitude, lat: record.latitude
      )
      .order(census_year: :desc)
      .first
  end

  def boundaries_loaded?
    scope.exists?
  end

  def scope
    Warehouse::GeoBoundary.by_type(boundary_type).where.not(geometry: nil)
  end

  def found(postal_code, city, boundary)
    Result.new(found: true, reason: :resolved, postal_code: postal_code, city: city, boundary: boundary)
  end

  def miss(reason, postal_code = nil, city = nil)
    Result.new(found: false, reason: reason, postal_code: postal_code, city: city, boundary: nil)
  end
end
