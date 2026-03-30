module SeniorBenefitCalculator
  class MarginalRateSweep
    INCOME_MAX = 200_000
    STEP = 500
    DELTA = 100 # $100 income change to measure marginal rate

    def initialize(policy_overrides = {})
      @stack = BenefitStack.new(policy_overrides)
    end

    # Sweeps income from $0 to $200K and calculates EMTR at each point
    # Returns array of data points for charting
    def sweep(base_profile)
      points = []

      (0..INCOME_MAX).step(STEP).each do |income|
        profile = base_profile.merge(pension_income: income)
        profile_plus = base_profile.merge(pension_income: income + DELTA)

        result = @stack.calculate(profile)
        result_plus = @stack.calculate(profile_plus)

        net_current = result[:summary][:net_income]
        net_plus = result_plus[:summary][:net_income]

        # EMTR = 1 - (change in net income / change in gross income)
        emtr = 1.0 - ((net_plus - net_current) / DELTA)

        points << {
          income: income,
          net_income: net_current.round(2),
          oas: result[:summary][:oas_benefit],
          gis: result[:summary][:gis_benefit],
          federal_tax: result[:summary][:federal_tax],
          age_credit: result[:age_credit][:age_credit_value],
          total_benefits: result[:summary][:total_benefits],
          emtr: emtr.clamp(0, 1).round(4)
        }
      end

      points
    end
  end
end
