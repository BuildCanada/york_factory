module SeniorBenefitCalculator
  class GisCalculator
    def initialize(policy:)
      @policy = policy
    end

    def calculate(marital_status:, income_excluding_oas:, employment_income: 0, tfsa_withdrawals: 0, corporate_income: 0)
      max_monthly = marital_status == "coupled" ? @policy[:gis_monthly_coupled] : @policy[:gis_monthly_single]
      threshold = marital_status == "coupled" ? @policy[:gis_income_threshold_coupled] : @policy[:gis_income_threshold_single]
      max_annual = max_monthly * 12

      # Build assessable income
      assessable = income_excluding_oas
      assessable += tfsa_withdrawals if @policy[:include_tfsa_in_gis]
      assessable += corporate_income if @policy[:include_corporate_income]

      # Employment income exemptions (always apply to employment portion)
      assessable_employment = apply_employment_exemptions(employment_income)

      # Non-employment income is everything else
      non_employment = [assessable - employment_income, 0].max

      total_assessable = non_employment + assessable_employment

      return zero_result(max_annual) if total_assessable >= threshold

      reduction = case @policy[:gis_clawback_regime]
      when "current"
        current_regime_reduction(total_assessable, max_annual)
      when "ccb_style"
        ccb_style_reduction(total_assessable, max_annual)
      when "custom"
        custom_regime_reduction(total_assessable, max_annual)
      else
        current_regime_reduction(total_assessable, max_annual)
      end

      net_annual = [max_annual - reduction, 0].max

      {
        gis_max_annual: max_annual.round(2),
        gis_reduction: reduction.round(2),
        gis_net_annual: net_annual.round(2),
        gis_monthly: (net_annual / 12).round(2),
        gis_assessable_income: total_assessable.round(2),
        gis_clawback_regime: @policy[:gis_clawback_regime]
      }
    end

    private

    def apply_employment_exemptions(employment_income)
      return 0.0 if employment_income <= 0

      exemption = @policy[:gis_employment_exemption]
      partial_exemption = @policy[:gis_employment_partial_exemption]

      if employment_income <= exemption
        0.0
      elsif employment_income <= exemption + partial_exemption
        (employment_income - exemption) * (1 - @policy[:gis_employment_partial_rate])
      else
        partial_exemption * (1 - @policy[:gis_employment_partial_rate]) +
          (employment_income - exemption - partial_exemption)
      end
    end

    # Current: 50 cents per dollar
    def current_regime_reduction(assessable, max_annual)
      [assessable * @policy[:gis_reduction_rate], max_annual].min
    end

    # CCB-style: two-tier graduated reduction
    def ccb_style_reduction(assessable, max_annual)
      lower_threshold = @policy[:gis_ccb_lower_threshold]
      upper_threshold = @policy[:gis_ccb_upper_threshold]
      lower_rate = @policy[:gis_ccb_lower_rate]
      upper_rate = @policy[:gis_ccb_upper_rate]

      reduction = if assessable <= lower_threshold
        0.0
      elsif assessable <= upper_threshold
        (assessable - lower_threshold) * lower_rate
      else
        (upper_threshold - lower_threshold) * lower_rate +
          (assessable - upper_threshold) * upper_rate
      end

      [reduction, max_annual].min
    end

    # Custom: single flat rate
    def custom_regime_reduction(assessable, max_annual)
      [assessable * @policy[:gis_custom_rate], max_annual].min
    end

    def zero_result(max_annual)
      { gis_max_annual: max_annual.round(2), gis_reduction: max_annual.round(2),
        gis_net_annual: 0.0, gis_monthly: 0.0, gis_assessable_income: 0.0,
        gis_clawback_regime: @policy[:gis_clawback_regime] }
    end
  end
end
