class CreateWarehouseMeasureFootnotes < ActiveRecord::Migration[8.1]
  # Links a source footnote to a measure directly, with no observation in
  # between. Used when a footnote explains the absence of data (indicator
  # retired, baseline not yet established, survey discontinued) — there is no
  # observation to attach it to, but the context belongs on the measure.
  def up
    execute <<~SQL
      CREATE TABLE warehouse.measure_footnotes (
        measure_id bigint NOT NULL REFERENCES warehouse.measures(id) ON DELETE CASCADE,
        source_footnote_id bigint NOT NULL REFERENCES warehouse.source_footnotes(id) ON DELETE CASCADE,
        created_at timestamp(6) without time zone DEFAULT now() NOT NULL,
        PRIMARY KEY (measure_id, source_footnote_id)
      );

      CREATE INDEX idx_measure_footnotes_footnote
        ON warehouse.measure_footnotes (source_footnote_id);
    SQL
  end

  def down
    execute "DROP TABLE warehouse.measure_footnotes"
  end
end
