module SeniorBenefitCalculator
  class IncomeTaxCalculator
    def initialize(policy:)
      @policy = policy
    end

    # Calculates federal income tax (simplified — no provincial)
    # taxable_income: total taxable income (employment + pension + investment + OAS)
    # age_credit_value: from AgeCreditCalculator
    def calculate(taxable_income:, age_credit_value: 0.0)
      return zero_result if taxable_income <= 0

      gross_tax = calculate_bracket_tax(taxable_income)

      # Non-refundable credits
      basic_personal_credit = @policy[:federal_basic_personal_amount] * 0.15
      total_credits = basic_personal_credit + age_credit_value

      net_tax = [gross_tax - total_credits, 0].max

      {
        federal_gross_tax: gross_tax.round(2),
        basic_personal_credit: basic_personal_credit.round(2),
        age_credit_applied: age_credit_value.round(2),
        total_credits: total_credits.round(2),
        federal_net_tax: net_tax.round(2),
        effective_rate: taxable_income > 0 ? (net_tax / taxable_income).round(4) : 0.0
      }
    end

    private

    def calculate_bracket_tax(income)
      brackets = @policy[:federal_tax_brackets]
      tax = 0.0
      prev_limit = 0.0

      brackets.each do |bracket|
        limit = bracket[:limit]
        rate = bracket[:rate]

        taxable_in_bracket = [income - prev_limit, 0].max
        taxable_in_bracket = [taxable_in_bracket, limit - prev_limit].min

        tax += taxable_in_bracket * rate
        prev_limit = limit

        break if income <= limit
      end

      tax
    end

    def zero_result
      { federal_gross_tax: 0.0, basic_personal_credit: 0.0, age_credit_applied: 0.0,
        total_credits: 0.0, federal_net_tax: 0.0, effective_rate: 0.0 }
    end
  end
end
