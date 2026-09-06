module Polls
  class CrosstabsWorkbook
    def initialize(poll)
      @poll = poll
    end

    def render
      report = JSON.parse(@poll.crosstabs_json.download)
      unless report["schemaVersion"] == 2 && report["tables"].is_a?(Array)
        raise ArgumentError, "Upload Surveyor schema-v2 crosstabs JSON with a tables array."
      end
      package = Axlsx::Package.new
      book = package.workbook
      book.escape_formulas = true
      heading = book.styles.add_style(bg_color: "8C3031", fg_color: "FFFFFF", b: true, sz: 13, alignment: { wrap_text: true })
      text = book.styles.add_style(font_name: "Arial", sz: 11, alignment: { wrap_text: true, vertical: :top })
      percent = book.styles.add_style(format_code: '0"%"', alignment: { horizontal: :right })
      book.add_worksheet(name: "Summary & Index") do |sheet|
        sheet.add_row [ "Build Canada", @poll.title_en ], style: heading
        sheet.add_row [ "Release date", @poll.published_at&.to_date&.iso8601 || "Draft" ], style: text
        sheet.add_row [ "Survey", report.dig("survey", "slug") ], style: text
        sheet.add_row [ "Universe", bilingual(report.dig("weighting", "universe")) ], style: text
        sheet.add_row [ "Weighting", report.dig("weighting", "method") ], style: text
        sheet.add_row [ "Benchmark", bilingual(report.dig("weighting", "benchmarkNote")) ], style: text
        %w[unweightedResponses effectiveResponses designEffect trimmedResponses].each do |key|
          sheet.add_row [ key.underscore.humanize, report.dig("weighting", key) ], style: text
        end
        sheet.add_row [ "Interpretation", "Percentages are weighted and rounded as in the source JSON. Blank cells are missing, never zero. Multiple selections can total more than 100%. Bases vary by question and subgroup." ], style: text, height: 60
        sheet.add_row [ "Privacy", report.dig("privacy", "note") ], style: text, height: 45
        Array(report["warnings"]).each { |warning| sheet.add_row [ "Warning", warning ], style: text, height: 45 }
        Array(report["translationFallbacks"]).each { |warning| sheet.add_row [ "Translation fallback", warning ], style: text }
        sheet.add_row []
        sheet.add_row [ "Sheet", "Question", "Question ID", "Type" ], style: heading
        report["tables"].each_with_index do |table, index|
          sheet.add_row [ "Q#{index + 1}", bilingual(table["question"]), table["id"], table["type"] ], style: text, height: 45
          sheet.add_hyperlink location: "'Q#{index + 1}'!A1", ref: "A#{sheet.rows.size}", target: :internal
        end
        sheet.column_widths 28, 90, 28, 20
      end
      report["tables"].each_with_index do |table, index|
        book.add_worksheet(name: "Q#{index + 1}") do |sheet|
          sheet.add_row [ "Back to summary & index" ], style: text
          sheet.add_hyperlink location: "'Summary & Index'!A1", ref: "A1", target: :internal
          sheet.add_row [ table["id"], bilingual(table["question"]) ], style: heading, height: 60
          sheet.add_row [ "Question type", table["type"] ], style: text
          (table["variants"] || table["armVariants"] || {}).each do |arm, variant|
            sheet.add_row [ "Variant: #{arm}", variant.is_a?(Hash) && variant.key?("prompt") ? JSON.pretty_generate(variant) : bilingual(variant) ], style: text, height: 90
          end
          columns = table.fetch("columns")
          groups = Array(report["breakdowns"]).index_by { |group| group["id"] }
          sheet.add_row [ "Breakdown", *columns.map { |c| bilingual(groups.dig(c["breakdownId"], "label") || c["breakdownId"]) } ], style: heading, height: 40
          sheet.add_row [ "Answer / base", *columns.map { |c| bilingual(c["label"]) } ], style: heading, height: 50
          freeze_row = sheet.rows.size
          table.fetch("rows").each do |row|
            values = columns.map do |column|
              value = row.fetch("values")[column.fetch("key")]
              raise ArgumentError, "Crosstab values must be numeric or null" unless value.nil? || (value.is_a?(Numeric) && value.finite?)
              value
            end
            sheet.add_row [ bilingual(row["label"]), *values ], style: [ text, *Array.new(values.size, row["kind"] == "weighted-percent" ? percent : text) ]
            (row["armVariants"] || {}).each { |arm, label| sheet.add_row [ "#{arm}: #{bilingual(label)}" ], style: text }
          end
          sheet.sheet_view.pane do |pane|
            pane.state = :frozen; pane.x_split = 1; pane.y_split = freeze_row; pane.top_left_cell = "B#{freeze_row + 1}"; pane.active_pane = :bottom_right
          end
          sheet.column_widths 55, *Array.new(columns.size, 24)
          sheet.page_setup.orientation = :landscape
          sheet.page_setup.fit_to_width = 1
          sheet.add_row []
          sheet.add_row [ "Breakdown semantics", "Membership and base definitions from Surveyor" ], style: heading
          groups.each { |id, group| sheet.add_row [ bilingual(group["label"] || id), JSON.generate(group["semantics"]) ], style: text, height: 35 }
        end
      end
      package.to_stream.read
    end

    private

    def bilingual(value)
      value.is_a?(Hash) ? [ value["en"], value["fr"] ].compact.uniq.join(" / ") : value.to_s
    end
  end
end
