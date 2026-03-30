module SeniorBenefitCalculator
  class ScenarioComparator
    def compare(profile:, current_policy: {}, proposed_policy:)
      current_stack = BenefitStack.new(current_policy)
      proposed_stack = BenefitStack.new(proposed_policy)

      current_result = current_stack.calculate(profile)
      proposed_result = proposed_stack.calculate(profile)

      current_sweep = MarginalRateSweep.new(current_policy).sweep(profile)
      proposed_sweep = MarginalRateSweep.new(proposed_policy).sweep(profile)

      {
        profile: profile,
        current: current_result,
        proposed: proposed_result,
        difference: build_difference(current_result[:summary], proposed_result[:summary]),
        current_marginal_rates: current_sweep,
        proposed_marginal_rates: proposed_sweep
      }
    end

    private

    def build_difference(current_summary, proposed_summary)
      {
        net_income_change: (proposed_summary[:net_income] - current_summary[:net_income]).round(2),
        oas_change: (proposed_summary[:oas_benefit] - current_summary[:oas_benefit]).round(2),
        gis_change: (proposed_summary[:gis_benefit] - current_summary[:gis_benefit]).round(2),
        tax_change: (proposed_summary[:federal_tax] - current_summary[:federal_tax]).round(2),
        total_benefits_change: (proposed_summary[:total_benefits] - current_summary[:total_benefits]).round(2)
      }
    end
  end
end
