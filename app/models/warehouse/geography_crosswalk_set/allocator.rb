class Warehouse::GeographyCrosswalkSet::Allocator
  # Spec rule: rates, ratios, medians, indexes, and per-capita values must NOT
  # be directly allocated. Only `additive` and `semi_additive` measures are
  # safe defaults; `compatibility` may upgrade or downgrade that.

  ALLOWED_AGGREGATION_TYPES = %w[additive semi_additive].freeze

  class IncompatibleMetric < StandardError; end

  Result = Struct.new(:derived, :skipped_reason, keyword_init: true)

  def self.allocate!(crosswalk_set:, canonical_observation:, target_geo:)
    new(crosswalk_set, canonical_observation, target_geo).call
  end

  def initialize(crosswalk_set, canonical_observation, target_geo)
    @set = crosswalk_set
    @observation = canonical_observation
    @measure = canonical_observation.measure
    @target_geo = target_geo
  end

  def call
    guard_compatibility!

    entry = @set.entries.find_by(
      from_geo_id: @observation.geo_boundary_id,
      to_geo_id:   @target_geo.id
    )
    return Result.new(derived: nil, skipped_reason: "no_entry") if entry.nil?

    value = @observation.value_numeric.to_f * entry.weight.to_f
    derived = Warehouse::DerivedObservation.create!(
      measure: @measure,
      from_canonical_observation: @observation,
      crosswalk_set: @set,
      original_geo_id: @observation.geo_boundary_id,
      derived_geo_id:  @target_geo.id,
      measurement_year: @observation.measurement_year,
      period_start: @observation.period_start,
      period_end:   @observation.period_end,
      period_type:  @observation.period_type,
      value_numeric: value,
      unit_id:       @observation.unit_id,
      derivation_method: "crosswalk_allocation",
      confidence:    entry.confidence,
      notes: "crosswalk weight #{entry.weight} from #{@observation.geo_boundary_id} to #{@target_geo.id}"
    )
    Result.new(derived: derived, skipped_reason: nil)
  end

  private

  def guard_compatibility!
    explicit = @set.compatibility_for(@measure)
    case explicit
    when "not_allowed"
      raise IncompatibleMetric, "crosswalk explicitly not_allowed for measure #{@measure.id}"
    when "recommended", "acceptable", "risky"
      return
    end

    return if ALLOWED_AGGREGATION_TYPES.include?(@measure.aggregation_type)
    raise IncompatibleMetric,
      "measure aggregation_type=#{@measure.aggregation_type} cannot be directly crosswalked " \
      "(use ratio_recompute on numerator and denominator instead)"
  end
end
