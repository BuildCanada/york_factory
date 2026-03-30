module SeniorBenefitCalculator
  class PolicyParams
    # 2025-26 federal defaults (Q1 2025 rates)
    DEFAULTS = {
      # OAS
      oas_monthly_65_74: 727.67,
      oas_monthly_75_plus: 800.44,
      oas_clawback_threshold: 90_997.0,
      oas_clawback_rate: 0.15,
      oas_eligibility_age: 65,
      oas_full_residence_years: 40,
      oas_min_residence_years: 10,

      # GIS (single)
      gis_monthly_single: 1086.88,
      gis_monthly_coupled: 654.23,
      gis_income_threshold_single: 21_624.0,
      gis_income_threshold_coupled: 28_560.0,
      gis_reduction_rate: 0.50,
      gis_employment_exemption: 5_000.0,
      gis_employment_partial_exemption: 10_000.0,
      gis_employment_partial_rate: 0.25,

      # GIS clawback regime: "current", "ccb_style", "custom"
      gis_clawback_regime: "current",

      # CCB-style parameters (used when gis_clawback_regime == "ccb_style")
      gis_ccb_lower_threshold: 5_000.0,
      gis_ccb_upper_threshold: 40_000.0,
      gis_ccb_lower_rate: 0.10,
      gis_ccb_upper_rate: 0.05,

      # Custom clawback (used when gis_clawback_regime == "custom")
      gis_custom_rate: 0.50,

      # Wealth test (disabled by default — not current policy)
      wealth_test_enabled: false,
      wealth_test_threshold: 2_000_000.0,
      wealth_test_home_exemption: 500_000.0,
      wealth_test_reduction_rate: 0.15,

      # TFSA inclusion for GIS (not current policy)
      include_tfsa_in_gis: false,

      # Corporate income attribution (not current policy)
      include_corporate_income: false,

      # Age credit
      age_credit_amount: 8_790.0,
      age_credit_clawback_threshold: 44_325.0,
      age_credit_clawback_rate: 0.15,

      # Federal income tax brackets 2025
      federal_tax_brackets: [
        { limit: 57_375.0, rate: 0.15 },
        { limit: 114_750.0, rate: 0.205 },
        { limit: 158_468.0, rate: 0.26 },
        { limit: 220_000.0, rate: 0.29 },
        { limit: Float::INFINITY, rate: 0.33 }
      ],
      federal_basic_personal_amount: 16_129.0,

      # Demographic projection
      inflation_rate: 0.02,
      population_growth_65_plus_rate: 0.03,
      wage_growth_rate: 0.025,
      worker_to_retiree_ratio_2025: 3.5,
      worker_to_retiree_ratio_2050: 2.3,
      total_oas_cost_2025_billions: 56.0,
      total_gis_cost_2025_billions: 16.0
    }.freeze

    attr_reader :params

    def initialize(overrides = {})
      @params = DEFAULTS.merge(overrides.symbolize_keys.slice(*DEFAULTS.keys))
    end

    def [](key)
      @params[key.to_sym]
    end

    def to_h
      @params
    end
  end
end
