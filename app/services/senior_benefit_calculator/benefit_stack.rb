module SeniorBenefitCalculator
  class BenefitStack
    def initialize(policy_overrides = {})
      @policy = PolicyParams.new(policy_overrides)
      @oas = OasCalculator.new(policy: @policy)
      @gis = GisCalculator.new(policy: @policy)
      @age_credit = AgeCreditCalculator.new(policy: @policy)
      @income_tax = IncomeTaxCalculator.new(policy: @policy)
    end

    def calculate(profile)
      age = profile[:age]
      marital_status = profile[:marital_status] || "single"
      years_in_canada = profile[:years_in_canada] || 40
      employment_income = profile[:employment_income] || 0
      pension_income = profile[:pension_income] || 0  # CPP + private pensions
      investment_income = profile[:investment_income] || 0
      rrif_income = profile[:rrif_income] || 0
      tfsa_withdrawals = profile[:tfsa_withdrawals] || 0
      corporate_income = profile[:corporate_income] || 0
      net_worth = profile[:net_worth] || 0
      home_value = profile[:home_value] || 0

      # Total income for tax and clawback purposes
      # (TFSA and corporate income may or may not be included depending on policy)
      taxable_income = employment_income + pension_income + investment_income + rrif_income
      income_excluding_oas = taxable_income

      # OAS calculation (uses net income for clawback)
      oas_result = @oas.calculate(
        age: age,
        years_in_canada: years_in_canada,
        net_income: taxable_income, # OAS clawback based on pre-OAS income
        net_worth: net_worth,
        home_value: home_value
      )

      # Total income including OAS (for tax purposes)
      total_taxable = taxable_income + oas_result[:oas_net_annual]

      # GIS calculation (uses income excluding OAS)
      gis_result = @gis.calculate(
        marital_status: marital_status,
        income_excluding_oas: income_excluding_oas,
        employment_income: employment_income,
        tfsa_withdrawals: tfsa_withdrawals,
        corporate_income: corporate_income
      )

      # Age credit
      age_credit_result = @age_credit.calculate(age: age, net_income: total_taxable)

      # Federal tax (on taxable income including OAS, not GIS)
      tax_result = @income_tax.calculate(
        taxable_income: total_taxable,
        age_credit_value: age_credit_result[:age_credit_value]
      )

      # Net income after everything
      total_benefits = oas_result[:oas_net_annual] + gis_result[:gis_net_annual]
      total_gross_income = taxable_income + total_benefits
      net_income = total_gross_income - tax_result[:federal_net_tax]

      {
        profile: profile,
        policy: @policy.to_h.except(:federal_tax_brackets),
        oas: oas_result,
        gis: gis_result,
        age_credit: age_credit_result,
        tax: tax_result,
        summary: {
          employment_income: employment_income.round(2),
          pension_income: pension_income.round(2),
          investment_income: investment_income.round(2),
          rrif_income: rrif_income.round(2),
          tfsa_withdrawals: tfsa_withdrawals.round(2),
          total_market_income: taxable_income.round(2),
          oas_benefit: oas_result[:oas_net_annual],
          gis_benefit: gis_result[:gis_net_annual],
          total_benefits: total_benefits.round(2),
          total_gross_income: total_gross_income.round(2),
          federal_tax: tax_result[:federal_net_tax],
          net_income: net_income.round(2),
          effective_tax_rate: total_gross_income > 0 ? (tax_result[:federal_net_tax] / total_gross_income).round(4) : 0.0,
          effective_benefit_rate: taxable_income > 0 ? (total_benefits / taxable_income).round(4) : 0.0
        }
      }
    end
  end
end
