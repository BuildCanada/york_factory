export interface Profile {
  age: number;
  marital_status: "single" | "coupled";
  years_in_canada: number;
  employment_income: number;
  pension_income: number;
  investment_income: number;
  rrif_income: number;
  tfsa_withdrawals: number;
  corporate_income: number;
  net_worth: number;
  home_value: number;
}

export interface PolicyParams {
  // OAS
  oas_monthly_65_74?: number;
  oas_monthly_75_plus?: number;
  oas_clawback_threshold?: number;
  oas_clawback_rate?: number;
  oas_eligibility_age?: number;

  // GIS
  gis_monthly_single?: number;
  gis_monthly_coupled?: number;
  gis_reduction_rate?: number;
  gis_clawback_regime?: "current" | "ccb_style" | "custom";
  gis_ccb_lower_threshold?: number;
  gis_ccb_upper_threshold?: number;
  gis_ccb_lower_rate?: number;
  gis_ccb_upper_rate?: number;
  gis_custom_rate?: number;

  // Wealth test
  wealth_test_enabled?: boolean;
  wealth_test_threshold?: number;
  wealth_test_home_exemption?: number;
  wealth_test_reduction_rate?: number;

  // Inclusion rules
  include_tfsa_in_gis?: boolean;
  include_corporate_income?: boolean;

  // Age credit
  age_credit_amount?: number;
  age_credit_clawback_threshold?: number;

  // Demographic projection
  inflation_rate?: number;
  population_growth_65_plus_rate?: number;
  wage_growth_rate?: number;
  total_oas_cost_2025_billions?: number;
  total_gis_cost_2025_billions?: number;
}

export interface BenefitSummary {
  employment_income: number;
  pension_income: number;
  investment_income: number;
  rrif_income: number;
  tfsa_withdrawals: number;
  total_market_income: number;
  oas_benefit: number;
  gis_benefit: number;
  total_benefits: number;
  total_gross_income: number;
  federal_tax: number;
  net_income: number;
  effective_tax_rate: number;
  effective_benefit_rate: number;
}

export interface CalculateResponse {
  profile: Profile;
  oas: Record<string, number>;
  gis: Record<string, number | string>;
  age_credit: Record<string, number>;
  tax: Record<string, number>;
  summary: BenefitSummary;
}

export interface MarginalRatePoint {
  income: number;
  net_income: number;
  oas: number;
  gis: number;
  federal_tax: number;
  age_credit: number;
  total_benefits: number;
  emtr: number;
}

export interface CompareResponse {
  current: CalculateResponse;
  proposed: CalculateResponse;
  difference: {
    net_income_change: number;
    oas_change: number;
    gis_change: number;
    tax_change: number;
    total_benefits_change: number;
  };
  current_marginal_rates: MarginalRatePoint[];
  proposed_marginal_rates: MarginalRatePoint[];
}

export interface ProjectionPoint {
  year: number;
  oas_cost_billions: number;
  gis_cost_billions: number;
  total_cost_billions: number;
  worker_to_retiree_ratio: number;
  cost_per_working_canadian: number;
  inflation_factor: number;
  population_growth_factor: number;
}

export interface ProjectionResponse {
  assumptions: Record<string, number>;
  projections: ProjectionPoint[];
}

export interface Persona {
  id: string;
  name: string;
  description: string;
  gaming_explanation: string;
  profile: Profile;
  result?: BenefitSummary;
}
