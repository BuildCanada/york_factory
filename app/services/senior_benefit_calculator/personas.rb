module SeniorBenefitCalculator
  class Personas
    SCENARIOS = {
      tfsa_maximizer: {
        name: "TFSA Maximizer",
        description: "Millionaire living off tax-free TFSA withdrawals. Zero taxable income, collects full OAS + GIS.",
        profile: {
          age: 70, marital_status: "single", years_in_canada: 40,
          employment_income: 0, pension_income: 0, investment_income: 0,
          rrif_income: 0, tfsa_withdrawals: 85_000, corporate_income: 0,
          net_worth: 1_200_000, home_value: 400_000
        },
        gaming_explanation: "TFSA withdrawals are invisible to OAS/GIS means tests. This person has $1.2M in assets but qualifies for maximum low-income supplements."
      },

      corporate_holdco: {
        name: "Corporate Holdco",
        description: "Business owner with $5M in a holding company. Pays no salary, takes tax-free capital dividends.",
        profile: {
          age: 68, marital_status: "single", years_in_canada: 40,
          employment_income: 0, pension_income: 0, investment_income: 0,
          rrif_income: 0, tfsa_withdrawals: 0, corporate_income: 120_000,
          net_worth: 5_000_000, home_value: 800_000
        },
        gaming_explanation: "Capital dividend account distributions from a CCPC are tax-free and not reported as personal income. This multi-millionaire collects full seniors benefits."
      },

      home_equity_senior: {
        name: "Home Equity Senior",
        description: "Lives in a $2.5M home, uses HELOC for expenses. Minimal taxable income.",
        profile: {
          age: 72, marital_status: "single", years_in_canada: 40,
          employment_income: 0, pension_income: 0, investment_income: 0,
          rrif_income: 12_000, tfsa_withdrawals: 0, corporate_income: 0,
          net_worth: 2_800_000, home_value: 2_500_000
        },
        gaming_explanation: "HELOC draws aren't income. Primary residence is fully exempt from any means test. A person living in a $2.5M home collects GIS designed for poverty relief."
      },

      income_splitter: {
        name: "Income Splitter Couple",
        description: "Affluent couple splitting $120K pension to stay below OAS clawback.",
        profile: {
          age: 67, marital_status: "coupled", years_in_canada: 40,
          employment_income: 0, pension_income: 60_000, investment_income: 10_000,
          rrif_income: 0, tfsa_withdrawals: 0, corporate_income: 0,
          net_worth: 900_000, home_value: 600_000
        },
        gaming_explanation: "Pension income splitting lets one spouse allocate up to 50% of pension to the other, keeping both below OAS recovery thresholds. Combined $120K household income pays no recovery tax."
      },

      median_canadian_senior: {
        name: "Median Canadian Senior",
        description: "Typical senior: modest CPP, small part-time job, renter. Faces punishing clawback on every dollar earned.",
        profile: {
          age: 69, marital_status: "single", years_in_canada: 40,
          employment_income: 5_000, pension_income: 9_800, investment_income: 0,
          rrif_income: 0, tfsa_withdrawals: 0, corporate_income: 0,
          net_worth: 35_000, home_value: 0
        },
        gaming_explanation: "No gaming — this person has no assets to shelter. Their $5K part-time earnings trigger GIS clawback. Effective marginal tax rate on additional income exceeds 70%."
      },

      median_working_canadian: {
        name: "Median Working Canadian (Comparison)",
        description: "35-year-old earning median income. For comparison: what does a working Canadian pay to fund seniors benefits?",
        profile: {
          age: 35, marital_status: "single", years_in_canada: 35,
          employment_income: 59_300, pension_income: 0, investment_income: 0,
          rrif_income: 0, tfsa_withdrawals: 0, corporate_income: 0,
          net_worth: 50_000, home_value: 0
        },
        gaming_explanation: "This worker pays full income tax + CPP/EI premiums. A portion of their federal tax funds OAS/GIS for seniors — including wealthy ones gaming the system. OAS alone costs ~$3,500 per working-age Canadian annually and rising."
      }
    }.freeze

    def self.all
      SCENARIOS.map do |key, scenario|
        scenario.merge(id: key.to_s)
      end
    end

    def self.find(id)
      scenario = SCENARIOS[id.to_sym]
      return nil unless scenario
      scenario.merge(id: id.to_s)
    end

    def self.calculate_all(policy_overrides = {})
      stack = BenefitStack.new(policy_overrides)

      SCENARIOS.map do |key, scenario|
        result = stack.calculate(scenario[:profile])
        {
          id: key.to_s,
          name: scenario[:name],
          description: scenario[:description],
          gaming_explanation: scenario[:gaming_explanation],
          profile: scenario[:profile],
          result: result[:summary]
        }
      end
    end
  end
end
