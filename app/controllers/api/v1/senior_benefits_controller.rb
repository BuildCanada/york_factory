module Api
  module V1
    class SeniorBenefitsController < ApplicationController
      # POST /api/v1/senior_benefits/calculate
      def calculate
        profile = parse_profile(params)
        policy_overrides = parse_policy(params[:policy] || {})

        stack = SeniorBenefitCalculator::BenefitStack.new(policy_overrides)
        result = stack.calculate(profile)

        render json: result
      end

      # POST /api/v1/senior_benefits/marginal_rates
      def marginal_rates
        profile = parse_profile(params)
        policy_overrides = parse_policy(params[:policy] || {})

        sweep = SeniorBenefitCalculator::MarginalRateSweep.new(policy_overrides)
        points = sweep.sweep(profile)

        render json: { profile: profile, data: points }
      end

      # POST /api/v1/senior_benefits/compare
      def compare
        profile = parse_profile(params)
        current_policy = parse_policy(params[:current_policy] || {})
        proposed_policy = parse_policy(params[:proposed_policy] || {})

        comparator = SeniorBenefitCalculator::ScenarioComparator.new
        result = comparator.compare(
          profile: profile,
          current_policy: current_policy,
          proposed_policy: proposed_policy
        )

        render json: result
      end

      # POST /api/v1/senior_benefits/project
      def project
        policy_overrides = parse_policy(params[:policy] || {})

        projector = SeniorBenefitCalculator::DemographicProjector.new(policy_overrides)
        result = projector.project

        render json: result
      end

      # GET /api/v1/senior_benefits/personas
      def personas
        policy_overrides = parse_policy(params[:policy] || {})

        if params[:calculate] == "true"
          render json: SeniorBenefitCalculator::Personas.calculate_all(policy_overrides)
        else
          render json: SeniorBenefitCalculator::Personas.all
        end
      end

      private

      def parse_profile(p)
        {
          age: p[:age]&.to_i || 70,
          marital_status: p[:marital_status] || "single",
          years_in_canada: p[:years_in_canada]&.to_i || 40,
          employment_income: p[:employment_income]&.to_f || 0,
          pension_income: p[:pension_income]&.to_f || 0,
          investment_income: p[:investment_income]&.to_f || 0,
          rrif_income: p[:rrif_income]&.to_f || 0,
          tfsa_withdrawals: p[:tfsa_withdrawals]&.to_f || 0,
          corporate_income: p[:corporate_income]&.to_f || 0,
          net_worth: p[:net_worth]&.to_f || 0,
          home_value: p[:home_value]&.to_f || 0
        }
      end

      def parse_policy(p)
        policy = {}
        # Numeric params
        %i[
          oas_monthly_65_74 oas_monthly_75_plus oas_clawback_threshold oas_clawback_rate
          oas_eligibility_age oas_full_residence_years oas_min_residence_years
          gis_monthly_single gis_monthly_coupled gis_income_threshold_single
          gis_income_threshold_coupled gis_reduction_rate gis_employment_exemption
          gis_employment_partial_exemption gis_employment_partial_rate
          gis_ccb_lower_threshold gis_ccb_upper_threshold gis_ccb_lower_rate gis_ccb_upper_rate
          gis_custom_rate wealth_test_threshold wealth_test_home_exemption
          wealth_test_reduction_rate age_credit_amount age_credit_clawback_threshold
          age_credit_clawback_rate inflation_rate population_growth_65_plus_rate
          wage_growth_rate total_oas_cost_2025_billions total_gis_cost_2025_billions
        ].each do |key|
          policy[key] = p[key].to_f if p[key].present?
        end

        # String params
        policy[:gis_clawback_regime] = p[:gis_clawback_regime] if p[:gis_clawback_regime].present?

        # Boolean params
        %i[wealth_test_enabled include_tfsa_in_gis include_corporate_income].each do |key|
          policy[key] = ActiveModel::Type::Boolean.new.cast(p[key]) if p.key?(key)
        end

        policy
      end
    end
  end
end
