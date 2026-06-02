class Warehouse::MetricComposition::Validator
  # Re-checks composition integrity for one (composition, year, observed_org, geo)
  # slice and writes one or more CompositionValidationResult rows.
  #
  # Validations:
  #   - components_sum_to_total: if a row with is_total=true exists, child rows must add up.
  #   - components_sum_to_100:   if composition.expected_total = 100, parts must add to 100.
  #
  # Tolerance: 0.5% of expected (or 0.01 absolute, whichever is larger).

  TOLERANCE_FRACTION = 0.005

  def self.run!(composition:, measurement_year:, observed_organization: nil, geo_boundary: nil)
    new(composition, measurement_year, observed_organization, geo_boundary).run!
  end

  def initialize(composition, measurement_year, observed_organization, geo_boundary)
    @composition = composition
    @measure = composition.measure
    @measurement_year = measurement_year
    @observed_organization = observed_organization
    @geo_boundary = geo_boundary
  end

  def run!
    results = []
    results << check_sum_to_total if total_observation
    results << check_sum_to_100 if @composition.expected_total.to_f == 100.0
    results.compact
  end

  private

  def total_observation
    @total_observation ||= slice_scope.where(is_total: true).order(approved_at: :desc).first
  end

  def component_observations
    @component_observations ||= slice_scope.where(is_total: false).where.not(component_id: nil).to_a
  end

  def slice_scope
    scope = Warehouse::CanonicalObservation
      .where(measure_id: @measure.id, composition_id: @composition.id, measurement_year: @measurement_year)
    scope = scope.where(observed_organization_id: @observed_organization&.id)
    scope = scope.where(geo_boundary_id: @geo_boundary&.id)
    scope
  end

  def check_sum_to_total
    actual = component_observations.sum { |o| o.value_numeric.to_f }
    expected = total_observation.value_numeric.to_f
    persist_result(
      validation_type: "components_sum_to_total",
      expected: expected, actual: actual
    )
  end

  def check_sum_to_100
    actual = component_observations.sum { |o| o.value_numeric.to_f }
    persist_result(
      validation_type: "components_sum_to_100",
      expected: 100.0, actual: actual
    )
  end

  def persist_result(validation_type:, expected:, actual:)
    diff = actual - expected
    tolerance = [ (expected.abs * TOLERANCE_FRACTION), 0.01 ].max
    status, severity = classify(diff.abs, tolerance, expected)

    Warehouse::CompositionValidationResult.create!(
      measure: @measure,
      composition: @composition,
      observed_organization: @observed_organization,
      geo_boundary: @geo_boundary,
      measurement_year: @measurement_year,
      validation_type: validation_type,
      expected_value: expected,
      actual_value: actual,
      difference: diff,
      status: status,
      severity: severity,
      message: status == "ok" ? "components match expected total" :
        "components sum to #{actual} but expected #{expected} (diff #{diff})"
    )
  end

  def classify(abs_diff, tolerance, expected)
    return [ "ok", nil ] if abs_diff <= tolerance
    ratio = expected.zero? ? abs_diff : abs_diff / expected.abs
    if ratio >= 0.1
      [ "fail", "critical" ]
    elsif ratio >= 0.02
      [ "fail", "high" ]
    else
      [ "warn", "medium" ]
    end
  end
end
