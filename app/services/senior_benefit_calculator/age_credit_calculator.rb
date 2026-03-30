module SeniorBenefitCalculator
  class AgeCreditCalculator
    CREDIT_RATE = 0.15 # Non-refundable credit rate

    def initialize(policy:)
      @policy = policy
    end

    def calculate(age:, net_income:)
      return zero_result if age < 65

      base_amount = @policy[:age_credit_amount]
      threshold = @policy[:age_credit_clawback_threshold]
      clawback_rate = @policy[:age_credit_clawback_rate]

      # Clawback of the age amount itself (not the credit)
      clawback = if net_income > threshold
        [(net_income - threshold) * clawback_rate, base_amount].min
      else
        0.0
      end

      remaining_amount = [base_amount - clawback, 0].max
      credit_value = remaining_amount * CREDIT_RATE

      {
        age_credit_base_amount: base_amount.round(2),
        age_credit_clawback: (clawback * CREDIT_RATE).round(2),
        age_credit_value: credit_value.round(2),
        age_credit_remaining_amount: remaining_amount.round(2)
      }
    end

    private

    def zero_result
      { age_credit_base_amount: 0.0, age_credit_clawback: 0.0,
        age_credit_value: 0.0, age_credit_remaining_amount: 0.0 }
    end
  end
end
