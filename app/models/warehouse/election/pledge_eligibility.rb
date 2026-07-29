# Decides whether a postal code puts someone inside the jurisdiction holding
# an election, so a pledge can be gated on residency.
#
# Geometry decides: the postal code's centroid is tested against the
# jurisdiction's census subdivision (CSD) boundary, because a CSD *is* the
# municipality. It catches what names can't — a postal code Canada Post labels
# "Woodbridge" or "Milton" but which sits inside Toronto or Hamilton — and
# needs no per-city maintenance.
#
# The city-name list is a safety net that can only *add* eligibility, never
# remove it, for two reasons:
#
#   * A postal code's centroid is the average of its delivery points, so near
#     a municipal line it can land on the wrong side. Measured against the full
#     postal table, that's 0.08%–0.9% of a city's codes — small, but each one
#     is a real resident who would otherwise be turned away.
#   * CSD boundaries may not be loaded at all (they come from
#     statcan_boundary_csd), and rejecting everyone in that case is worse than
#     judging them by name.
#
# City names collide across provinces (Richmond BC, Stoney Creek NB, Dundas
# NB), so the province check is not optional, and a list has to name every
# amalgamated community a city absorbed — a Waterdown address is a Hamilton
# address. `cities` is optional: a region that only sets csd_uid is judged
# purely on geometry.
#
# Elections in a jurisdiction with no rule are ungated: a region we haven't
# taught this class about accepts every pledge rather than rejecting everyone.
class Warehouse::Election::PledgeEligibility < ActiveRecord::AssociatedObject
  # csd_uid: the StatCan census subdivision to test the postal code's centroid
  #         against — the authoritative check, which makes `cities` a fallback.
  #         Keyed by UID, not name: Ontario has two CSDs called "Hamilton", the
  #         city (3525005, 1118 km²) and a township in Northumberland
  #         (3514019, 256 km²), and matching on the name can silently pick the
  #         wrong one.
  # cities: the values Canada Post writes for addresses inside the city,
  #         including the ones it absorbed on amalgamation.
  # fsa_pattern: only where a city owns whole forward sortation areas, which
  #         lets an unrecognized postal code still be judged. Toronto owns
  #         every "M" FSA; nowhere else here is that clean (L6 spans Brampton,
  #         Oakville, Markham and Vaughan; K0A spans Ottawa and half of
  #         eastern Ontario).
  RULES = {
    "toronto" => {
      province: "ON", csd_uid: "3520005", fsa_pattern: /\AM/,
      cities: [ "TORONTO", "NORTH YORK", "SCARBOROUGH", "ETOBICOKE", "YORK", "EAST YORK" ]
    },
    "brampton" => {
      province: "ON", csd_uid: "3521010",
      cities: [ "BRAMPTON" ]
    },
    "hamilton" => {
      province: "ON", csd_uid: "3525005",
      cities: [
        "HAMILTON", "STONEY CREEK", "DUNDAS", "ANCASTER", "WATERDOWN", "BINBROOK",
        "MOUNT HOPE", "MILLGROVE", "FREELTON", "CARLISLE", "LYNDEN", "COPETOWN",
        "JERSEYVILLE", "TROY", "ROCKTON", "SHEFFIELD"
      ]
    },
    "ottawa" => {
      province: "ON", csd_uid: "3506008",
      cities: [
        "OTTAWA", "NEPEAN", "KANATA", "GLOUCESTER", "ORLEANS", "VANIER", "ROCKCLIFFE",
        "STITTSVILLE", "MANOTICK", "GREELY", "CUMBERLAND", "NAVAN", "RICHMOND", "VARS",
        "NORTH GOWER", "CARP", "OSGOODE", "VERNON", "METCALFE", "KARS", "KENMORE",
        "KINBURN", "DUNROBIN", "WOODLAWN", "FITZROY HARBOUR", "CARLSBAD SPRINGS",
        "EDWARDS", "MUNSTER", "ASHTON", "RAMSAYVILLE", "SARSFIELD"
      ]
    }
  }.freeze

  REASONS = %i[
    no_rule no_postal_code malformed_postal_code unknown_postal_code
    postal_data_unavailable inside_boundary outside_boundary
    city_match city_mismatch fsa_match
  ].freeze

  Result = Data.define(:eligible, :reason, :postal_code, :city) do
    def eligible? = eligible

    # True where we could not judge, as opposed to judging someone outside —
    # the client can ask them to check what they typed instead of turning
    # them away.
    def indeterminate? = %i[malformed_postal_code unknown_postal_code].include?(reason)
  end

  def rule
    RULES[election.jurisdiction&.slug]
  end

  def gated?
    rule.present?
  end

  # The name to show a pledger who turns out to be outside the region.
  def region_name
    election.jurisdiction&.name
  end

  def check(raw_postal_code)
    return result(true, :no_rule) if rule.nil?
    # A blank postal code has always been let through (ward-scoped pledge links
    # that never collected one); the public form always sends one.
    return result(true, :no_postal_code) if raw_postal_code.blank?

    normalized = Warehouse::PostalCode.normalize(raw_postal_code)
    return result(false, :malformed_postal_code) if normalized.nil?

    record = Warehouse::PostalCode.lookup(normalized)
    return unrecognized(normalized) if record.nil?

    boundary = csd_boundary
    return result(true, :inside_boundary, normalized, record.city) if boundary && contains?(boundary, record)

    # Geometry said no, or had nothing to say. The city's own name for the place
    # still counts — a centroid can sit just outside the line it belongs to.
    return result(true, :city_match, normalized, record.city) if city_match?(record, normalized)

    result(false, boundary ? :outside_boundary : :city_mismatch, normalized, record.city)
  end

  private

  # Postal codes are added faster than our snapshot of them: a code we don't
  # know still counts where the city owns the whole FSA.
  #
  # A code we can't find because no postal codes are loaded at all is a
  # different situation, and one where rejecting would turn every real resident
  # away (warehouse.postal_codes is populated by rake postal_codes:import, not
  # by migrating). We let those through and say so.
  def unrecognized(normalized)
    return result(true, :fsa_match, normalized) if rule[:fsa_pattern] && fsa_matches?(normalized)

    unless postal_data_loaded?
      Rails.logger.warn "[PledgeEligibility] No #{rule[:province]} postal codes loaded — " \
        "cannot check residency for #{election.slug}, allowing #{normalized}"
      return result(true, :postal_data_unavailable, normalized)
    end

    result(false, :unknown_postal_code, normalized)
  end

  def postal_data_loaded?
    Warehouse::PostalCode.in_province(rule[:province]).exists?
  end

  def csd_boundary
    return @csd_boundary if defined?(@csd_boundary)

    @csd_boundary = rule[:csd_uid] && Warehouse::GeoBoundary
      .by_type("csd")
      .where(geo_uid: rule[:csd_uid])
      .where.not(geometry: nil)
      .order(census_year: :desc)
      .first
  end

  def contains?(boundary, record)
    Warehouse::GeoBoundary.where(id: boundary.id)
      .where(
        "ST_Intersects(geometry, ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)::geography)",
        lon: record.longitude, lat: record.latitude
      )
      .exists?
  end

  def city_match?(record, normalized)
    city_names.include?(record.city.to_s.upcase) && province_matches?(record) && fsa_matches?(normalized)
  end

  def city_names
    @city_names ||= Array(rule[:cities]).map(&:upcase).to_set
  end

  def province_matches?(record)
    rule[:province].blank? || record.province_code.to_s.casecmp?(rule[:province])
  end

  def fsa_matches?(normalized)
    rule[:fsa_pattern].nil? || rule[:fsa_pattern].match?(normalized.to_s)
  end

  def result(eligible, reason, postal_code = nil, city = nil)
    Result.new(eligible: eligible, reason: reason, postal_code: postal_code, city: city)
  end
end
