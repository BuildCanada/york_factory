class AddMetadataToWarehouseMeasures < ActiveRecord::Migration[8.1]
  AGGREGATION_TYPES = %w[
    additive semi_additive average ratio median index rate part_of_whole non_aggregable unknown
  ].freeze

  FREQUENCIES = %w[annual fiscal_year quarterly monthly point_in_time irregular unknown].freeze

  def up
    execute <<~SQL
      ALTER TABLE warehouse.measures
        ADD COLUMN aggregation_type varchar NOT NULL DEFAULT 'unknown',
        ADD COLUMN numerator_measure_id   bigint REFERENCES warehouse.measures(id),
        ADD COLUMN denominator_measure_id bigint REFERENCES warehouse.measures(id),
        ADD COLUMN higher_is_bad boolean,
        ADD COLUMN frequency varchar,
        ADD COLUMN category  varchar,
        ADD CONSTRAINT measures_aggregation_type_check
          CHECK (aggregation_type IN (#{AGGREGATION_TYPES.map { |s| "'#{s}'" }.join(',')})),
        ADD CONSTRAINT measures_frequency_check
          CHECK (frequency IS NULL OR frequency IN (#{FREQUENCIES.map { |s| "'#{s}'" }.join(',')})),
        ADD CONSTRAINT measures_ratio_has_components
          CHECK (
            aggregation_type NOT IN ('ratio','rate')
            OR (numerator_measure_id IS NOT NULL AND denominator_measure_id IS NOT NULL)
            OR aggregation_type = 'unknown'
          ),
        ADD CONSTRAINT measures_no_self_ratio
          CHECK (
            (numerator_measure_id IS NULL OR numerator_measure_id <> id)
            AND (denominator_measure_id IS NULL OR denominator_measure_id <> id)
          )
    SQL

    # Seed aggregation_type for existing measures from their unit's kind.
    # Ratio / rate measures stay 'unknown' until a reviewer fills in
    # numerator_measure_id and denominator_measure_id (the constraint above).
    execute <<~SQL
      UPDATE warehouse.measures m
      SET aggregation_type = CASE u.kind
        WHEN 'absolute'    THEN 'additive'
        WHEN 'qualitative' THEN 'non_aggregable'
        ELSE 'unknown'
      END
      FROM warehouse.units u
      WHERE u.id = m.unit_id
    SQL

    add_index "warehouse.measures", :aggregation_type, name: "idx_measures_aggregation_type"
    add_index "warehouse.measures", :category, name: "idx_measures_category"
    add_index "warehouse.measures", :numerator_measure_id, name: "idx_measures_numerator"
    add_index "warehouse.measures", :denominator_measure_id, name: "idx_measures_denominator"
  end

  def down
    execute "ALTER TABLE warehouse.measures DROP CONSTRAINT IF EXISTS measures_no_self_ratio"
    execute "ALTER TABLE warehouse.measures DROP CONSTRAINT IF EXISTS measures_ratio_has_components"
    execute "ALTER TABLE warehouse.measures DROP CONSTRAINT IF EXISTS measures_frequency_check"
    execute "ALTER TABLE warehouse.measures DROP CONSTRAINT IF EXISTS measures_aggregation_type_check"
    %w[denominator_measure_id numerator_measure_id higher_is_bad frequency category aggregation_type].each do |c|
      execute "ALTER TABLE warehouse.measures DROP COLUMN IF EXISTS #{c}"
    end
  end
end
