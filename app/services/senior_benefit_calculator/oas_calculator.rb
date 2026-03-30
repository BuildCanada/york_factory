module SeniorBenefitCalculator
  class OasCalculator
    def initialize(policy:)
      @policy = policy
    end

    def calculate(age:, years_in_canada:, net_income:, net_worth: 0, home_value: 0)
      return zero_result if age < @policy[:oas_eligibility_age]

      base_monthly = age >= 75 ? @policy[:oas_monthly_75_plus] : @policy[:oas_monthly_65_74]

      # Partial pension based on residency
      residence_fraction = if years_in_canada >= @policy[:oas_full_residence_years]
        1.0
      elsif years_in_canada >= @policy[:oas_min_residence_years]
        years_in_canada.to_f / @policy[:oas_full_residence_years]
      else
        0.0
      end

      gross_annual = base_monthly * residence_fraction * 12

      # OAS recovery tax (clawback)
      recovery_tax = if net_income > @policy[:oas_clawback_threshold]
        excess = net_income - @policy[:oas_clawback_threshold]
        (excess * @policy[:oas_clawback_rate]).clamp(0, gross_annual)
      else
        0.0
      end

      # Wealth test reduction (if enabled)
      wealth_reduction = calculate_wealth_reduction(gross_annual - recovery_tax, net_worth, home_value)

      net_annual = [gross_annual - recovery_tax - wealth_reduction, 0].max

      {
        oas_gross_annual: gross_annual.round(2),
        oas_recovery_tax: recovery_tax.round(2),
        oas_wealth_reduction: wealth_reduction.round(2),
        oas_net_annual: net_annual.round(2),
        oas_monthly: (net_annual / 12).round(2),
        residence_fraction: residence_fraction.round(4)
      }
    end

    private

    def calculate_wealth_reduction(remaining_benefit, net_worth, home_value)
      return 0.0 unless @policy[:wealth_test_enabled]

      assessable_wealth = net_worth - [home_value, @policy[:wealth_test_home_exemption]].min
      return 0.0 if assessable_wealth <= @policy[:wealth_test_threshold]

      excess = assessable_wealth - @policy[:wealth_test_threshold]
      deemed_income = excess * @policy[:wealth_test_reduction_rate]
      # Reduce OAS by 15% of deemed income from excess wealth
      [deemed_income * @policy[:oas_clawback_rate], remaining_benefit].min
    end

    def zero_result
      { oas_gross_annual: 0.0, oas_recovery_tax: 0.0, oas_wealth_reduction: 0.0,
        oas_net_annual: 0.0, oas_monthly: 0.0, residence_fraction: 0.0 }
    end
  end
end
