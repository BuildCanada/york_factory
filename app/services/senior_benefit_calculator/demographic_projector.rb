module SeniorBenefitCalculator
  class DemographicProjector
    BASE_YEAR = 2025
    PROJECTION_END = 2050

    def initialize(policy_overrides = {})
      @policy = PolicyParams.new(policy_overrides)
    end

    def project
      years = (BASE_YEAR..PROJECTION_END).map do |year|
        offset = year - BASE_YEAR
        inflation_factor = (1 + @policy[:inflation_rate]) ** offset
        pop_growth_factor = (1 + @policy[:population_growth_65_plus_rate]) ** offset

        # Worker-to-retiree ratio declines linearly
        ratio_decline = (@policy[:worker_to_retiree_ratio_2025] - @policy[:worker_to_retiree_ratio_2050]) *
          (offset.to_f / (PROJECTION_END - BASE_YEAR))
        worker_retiree_ratio = @policy[:worker_to_retiree_ratio_2025] - ratio_decline

        # OAS costs grow with inflation (indexed) and population
        oas_cost = @policy[:total_oas_cost_2025_billions] * inflation_factor * pop_growth_factor
        gis_cost = @policy[:total_gis_cost_2025_billions] * inflation_factor * pop_growth_factor
        total_cost = oas_cost + gis_cost

        # GDP proxy: grows with wage growth and working population
        wage_factor = (1 + @policy[:wage_growth_rate]) ** offset
        # Working population shrinks relative to total as seniors grow
        gdp_index = wage_factor * 100 # Indexed to 100

        # Cost per working-age Canadian (rough)
        # Assume ~20M working-age Canadians in 2025, growing slowly
        working_pop_millions = 20.0 * (1 + 0.005) ** offset # 0.5% growth
        cost_per_worker = (total_cost * 1_000_000_000) / (working_pop_millions * 1_000_000)

        {
          year: year,
          oas_cost_billions: oas_cost.round(1),
          gis_cost_billions: gis_cost.round(1),
          total_cost_billions: total_cost.round(1),
          worker_to_retiree_ratio: worker_retiree_ratio.round(2),
          cost_per_working_canadian: cost_per_worker.round(0),
          inflation_factor: inflation_factor.round(3),
          population_growth_factor: pop_growth_factor.round(3)
        }
      end

      {
        assumptions: {
          inflation_rate: @policy[:inflation_rate],
          population_growth_65_plus_rate: @policy[:population_growth_65_plus_rate],
          wage_growth_rate: @policy[:wage_growth_rate],
          worker_to_retiree_ratio_2025: @policy[:worker_to_retiree_ratio_2025],
          worker_to_retiree_ratio_2050: @policy[:worker_to_retiree_ratio_2050],
          base_oas_cost_billions: @policy[:total_oas_cost_2025_billions],
          base_gis_cost_billions: @policy[:total_gis_cost_2025_billions]
        },
        projections: years
      }
    end
  end
end
