class Warehouse::Alert::Evaluator
  # Evaluates a single alert against canonical_observations. Returns an
  # AlertEvent if the condition fired this run, nil otherwise.
  #
  # Supports `above`, `below`, `percent_change`, `absolute_change`, and
  # `missing_update`. Other condition_types are reserved for later phases
  # (rank_change, new_definition, etc.) and currently no-op.

  def initialize(alert)
    @alert = alert
  end

  def evaluate!
    return nil unless @alert.enabled

    case @alert.condition_type
    when "above"            then check_threshold(:>,   @alert.threshold_value)
    when "below"            then check_threshold(:<,   @alert.threshold_value)
    when "percent_change"   then check_change(:percent)
    when "absolute_change"  then check_change(:absolute)
    when "missing_update"   then check_missing_update
    end
  end

  private

  def slice_scope
    scope = Warehouse::CanonicalObservation.where(measure_id: @alert.measure_id)
    scope = scope.where(observed_organization_id: @alert.observed_organization_id) if @alert.observed_organization_id
    scope = scope.where(geo_boundary_id: @alert.geo_boundary_id)                   if @alert.geo_boundary_id
    scope = scope.where(jurisdiction_id: @alert.jurisdiction_id)                   if @alert.jurisdiction_id
    scope
  end

  def latest
    slice_scope.order(measurement_year: :desc, approved_at: :desc).first
  end

  def previous
    return nil unless latest
    slice_scope.where("measurement_year < ?", latest.measurement_year)
      .order(measurement_year: :desc, approved_at: :desc).first
  end

  def check_threshold(comparator, threshold)
    return nil unless threshold && (obs = latest)&.value_numeric
    return nil unless obs.value_numeric.public_send(comparator, threshold)
    record_event!(canonical_observation: obs, observed_value: obs.value_numeric,
                  comparison_value: threshold,
                  message: "value #{obs.value_numeric} #{comparator} threshold #{threshold}")
  end

  def check_change(kind)
    return nil unless @alert.threshold_value && (curr = latest) && (prev = previous)
    return nil unless curr.value_numeric && prev.value_numeric
    diff = curr.value_numeric - prev.value_numeric
    magnitude = kind == :percent ? (prev.value_numeric.zero? ? nil : (diff / prev.value_numeric.abs) * 100) : diff
    return nil if magnitude.nil?
    return nil if magnitude.abs < @alert.threshold_value.abs
    record_event!(canonical_observation: curr, observed_value: curr.value_numeric,
                  comparison_value: prev.value_numeric,
                  message: "#{kind} change #{magnitude.round(2)} exceeds threshold #{@alert.threshold_value}")
  end

  def check_missing_update
    return nil unless @alert.threshold_value # days_since_last_update threshold
    obs = latest
    deadline_days = @alert.threshold_value.to_f
    return nil if obs && obs.approved_at && (Time.current - obs.approved_at) < deadline_days.days
    record_event!(canonical_observation: obs,
                  observed_value: obs&.value_numeric,
                  comparison_value: deadline_days,
                  message: "no canonical observation approved within #{deadline_days} days")
  end

  def record_event!(canonical_observation:, observed_value:, comparison_value:, message:)
    @alert.events.create!(
      canonical_observation: canonical_observation,
      observed_value: observed_value,
      comparison_value: comparison_value,
      message: message,
      details: { alert_id: @alert.id, condition_type: @alert.condition_type,
                 measure_id: @alert.measure_id, observed_at: Time.current.iso8601 }
    )
  end
end
