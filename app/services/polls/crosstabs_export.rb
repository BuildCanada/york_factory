module Polls
  # The customer export boundary. Source uploads remain available to editors;
  # downloads and generated workbooks always pass through this projection.
  class CrosstabsExport
    MINIMUM_RESPONSES = 50
    ROW_KINDS = %w[unweighted-sample-size weighted-sample-size weighted-percent].freeze

    def initialize(source)
      @source = source
    end

    def render
      report = JSON.parse(@source)
      unless report.is_a?(Hash) && report["schemaVersion"] == 2 && report["tables"].is_a?(Array)
        raise ArgumentError, "Upload Surveyor schema-v2 crosstabs JSON with a tables array."
      end
      {
        "schemaVersion" => 2,
        "survey" => report.fetch("survey", {}).slice("slug", "title"),
        "weighting" => public_weighting(report.fetch("weighting", {})),
        "privacy" => { "minimumResponses" => MINIMUM_RESPONSES, "smallCellSuppression" => true },
        "breakdowns" => Array(report["breakdowns"]).map { |group| group.slice("id", "label", "kind", "question") },
        "tables" => report["tables"].map { |table| public_table(table, include_arms: true) }
      }
    end

    private

    def public_weighting(weighting)
      result = weighting.slice("universe", "benchmarkNote")
      count = weighting["unweightedResponses"]
      result["unweightedResponses"] = count if publishable?(count)
      result
    end

    def publishable?(count)
      count.is_a?(Numeric) && count.finite? && count >= MINIMUM_RESPONSES
    end

    def public_table(table, include_arms: false)
      columns = table.fetch("columns").reject { |column| column["id"].to_s.downcase == "unknown" || column["key"].to_s.split(":").last == "unknown" }
      rows = table.fetch("rows").select { |row| ROW_KINDS.include?(row["kind"]) }
      base = rows.find { |row| row["kind"] == "unweighted-sample-size" }
      suppressed = columns.reject { |column| publishable?(base&.dig("values", column.fetch("key"))) }.map { |column| column.fetch("key") }
      result = table.slice("id", "label", "type", "question", "variants", "armVariants").merge(
        "columns" => columns.map { |column| column.slice("key", "id", "breakdownId", "label") },
        "suppressedColumns" => suppressed,
        "rows" => rows.map do |row|
          row.slice("id", "kind", "label", "armVariants").merge("values" => columns.to_h do |column|
            key = column.fetch("key")
            value = row.fetch("values")[key]
            raise ArgumentError, "Crosstab values must be numeric or null" unless value.nil? || (value.is_a?(Numeric) && value.finite?)
            [ key, suppressed.include?(key) ? nil : value ]
          end)
        end
      )
      if include_arms
        arms = table["arms"].is_a?(Array) ? table["arms"] : legacy_arms(table)
        result["arms"] = arms.map { |arm| public_table(arm) } if arms.any?
      end
      result
    end

    # Older uploads have arm totals as columns, but no arm-by-demographic cells.
    # Transpose only the supplied totals; never copy pooled demographic results.
    def legacy_arms(table)
      arm_columns = table.fetch("columns").select { |column| column["breakdownId"] == "arm" && column["id"] != "unknown" }
      total = table.fetch("columns").find { |column| column["breakdownId"] == "overall" }
      return [] unless total
      arm_columns.map do |column|
        arm = column.fetch("id")
        variant = table.dig("variants", arm)
        {
          "id" => arm, "label" => column["label"], "type" => table["type"],
          "question" => variant&.fetch("prompt", nil) || table.dig("armVariants", arm) || table["question"],
          "columns" => [ total ],
          "rows" => table.fetch("rows").map do |row|
            row.slice("id", "kind").merge(
              "label" => variant&.dig("options", row["id"]) || row.dig("armVariants", arm) || row["label"],
              "values" => { total.fetch("key") => row.fetch("values")[column.fetch("key")] }
            )
          end
        }
      end
    end
  end
end
