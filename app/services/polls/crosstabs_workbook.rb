module Polls
  class CrosstabsWorkbook
    VERSION = 2

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
      styles = workbook_styles(book)
      book.add_worksheet(name: "Summary & Index") do |sheet|
        sheet.add_row [ "Build Canada", @poll.title_en ], style: styles[:title], height: [ 64, text_height(@poll.title_en, 60) ].max
        sheet.add_row [ "Release date", @poll.published_at&.strftime("%B %-d, %Y") || "Draft" ], style: styles[:text], height: 28
        {
          "Survey population" => bilingual(report.dig("weighting", "universe")),
          "Population benchmark" => bilingual(report.dig("weighting", "benchmarkNote")),
          "Sample size" => report.dig("weighting", "unweightedResponses")
        }.each do |label, value|
          sheet.add_row [ label, value ], style: styles[:text], height: text_height(value, 90) if value.present?
        end
        sheet.add_row [ "Reading the results", "Percentages are weighted and rounded to whole numbers. Blank cells indicate unavailable results. Multiple selections can total more than 100%. Sample sizes vary by question and group. Unknown demographic categories are omitted; overall totals include all respondents." ], style: styles[:text], height: 80
        sheet.add_row []
        sheet.add_row [ "Question", "Select a question to view results" ], style: styles[:heading], height: 30
        report["tables"].each_with_index do |table, index|
          sheet.add_row [ "Question #{index + 1}", bilingual(table["question"]) ], style: [ styles[:link], styles[:text] ], height: text_height(bilingual(table["question"]), 90)
          sheet.add_hyperlink location: "'Q#{index + 1}'!A1", ref: "A#{sheet.rows.size}", target: :internal
        end
        sheet.column_widths 28, 100
        sheet.sheet_view.show_grid_lines = false
      end
      report["tables"].each_with_index do |table, index|
        book.add_worksheet(name: "Q#{index + 1}") do |sheet|
          columns = table.fetch("columns").reject { |column| unknown_category?(column) }
          last_column = Axlsx.col_ref([ columns.size, 1 ].max)
          sheet.add_row [ "Back to summary & index" ], style: styles[:link], height: 26
          sheet.add_hyperlink location: "'Summary & Index'!A1", ref: "A1", target: :internal
          sheet.add_row [ "Question #{index + 1}", bilingual(table["question"]) ], style: styles[:title], height: text_height(bilingual(table["question"]), [ columns.size * 14, 14 ].max) + 16
          sheet.merge_cells("B2:#{last_column}2") if columns.size > 1
          variants = table["variants"] || table["armVariants"] || {}
          arm_numbers = (variants.keys | table.fetch("rows").flat_map { |row| (row["armVariants"] || {}).keys }).each_with_index.to_h { |arm, n| [ arm, n + 1 ] }
          variants.each do |arm, variant|
            wording = if variant.is_a?(Hash) && variant.key?("prompt")
              ([ variant["prompt"], variant["description"], *Array(variant["options"]&.values), *variant.values_at("minLabel", "maxLabel", "trueLabel", "falseLabel") ].compact.map { |value| bilingual(value) }).reject(&:blank?).join("\n")
            else
              bilingual(variant)
            end
            sheet.add_row [ "Version #{arm_numbers.fetch(arm)}", wording ], style: styles[:text], height: text_height(wording, [ columns.size * 22, 22 ].max)
            sheet.merge_cells("B#{sheet.rows.size}:#{last_column}#{sheet.rows.size}") if columns.size > 1
          end
          groups = Array(report["breakdowns"]).index_by { |group| group["id"] }
          labels = columns.map do |column|
            group_data = groups[column["breakdownId"]]
            group = group_data&.fetch("kind", nil) == "overall" ? nil : bilingual(group_data&.fetch("label", nil))
            [ group.presence, bilingual(column["label"]) ].compact.uniq.join("\n")
          end
          sheet.add_row [ "Answer / sample size", *labels ], style: styles[:heading], height: labels.map { |label| text_height(label, 20) }.max || 40
          freeze_row = sheet.rows.size
          table.fetch("rows").each_with_index do |row, row_index|
            values = columns.map do |column|
              value = row.fetch("values")[column.fetch("key")]
              raise ArgumentError, "Crosstab values must be numeric or null" unless value.nil? || (value.is_a?(Numeric) && value.finite?)
              value
            end
            band = row_index.even? ? :even : :odd
            number_style = row["kind"] == "weighted-percent" ? styles[:percent][band] : styles[:number][band]
            label = bilingual(row["label"])
            sheet.add_row [ label, *values ], style: [ styles[band], *Array.new(values.size, number_style) ], height: text_height(label, 48)
            (row["armVariants"] || {}).each do |arm, wording|
              label = "Version #{arm_numbers.fetch(arm)}: #{bilingual(wording)}"
              sheet.add_row [ label ], style: styles[:text], height: text_height(label, 48)
            end
          end
          sheet.sheet_view.show_grid_lines = false
          sheet.sheet_view.pane do |pane|
            pane.state = :frozen; pane.x_split = 1; pane.y_split = freeze_row; pane.top_left_cell = "B#{freeze_row + 1}"; pane.active_pane = :bottom_right
          end
          sheet.column_widths 55, *Array.new(columns.size, 24)
          sheet.page_setup.orientation = :landscape
          sheet.page_setup.fit_to_width = 1
          sheet.page_setup.fit_to_height = 0
        end
      end
      errors = package.validate
      raise ArgumentError, "Invalid workbook: #{errors.map(&:message).join('; ').truncate(1000)}" if errors.any?
      package.to_stream.read
    end

    private

    def unknown_category?(column)
      column["id"].to_s.casecmp?("unknown") || column["key"].to_s.split(":").last.to_s.casecmp?("unknown")
    end

    def text_height(value, width)
      lines = value.to_s.split("\n").sum { |line| [ (line.length.to_f / width).ceil, 1 ].max }
      [ 32, lines * 16 + 16 ].max.clamp(32, 409)
    end

    def workbook_styles(book)
      base = { font_name: "Arial", fg_color: "272727", sz: 11, alignment: { wrap_text: true, vertical: :center } }
      styles = {
        title: book.styles.add_style(**base, bg_color: "272727", fg_color: "FFFFFF", b: true, sz: 16),
        heading: book.styles.add_style(**base, bg_color: "272727", fg_color: "FFFFFF", b: true),
        text: book.styles.add_style(**base, bg_color: "F3E7DC"),
        link: book.styles.add_style(**base, bg_color: "F3E7DC", fg_color: "8C3031", u: true),
        percent: {}, number: {}
      }
      { even: "F3E7DC", odd: "FAF5F0" }.each do |band, color|
        styles[band] = book.styles.add_style(**base, bg_color: color)
        numeric = base.merge(bg_color: color, alignment: { horizontal: :right, vertical: :center })
        styles[:number][band] = book.styles.add_style(**numeric, format_code: "#,##0")
        styles[:percent][band] = book.styles.add_style(**numeric, format_code: '0\\%')
      end
      styles
    end

    def bilingual(value)
      value.is_a?(Hash) ? [ value["en"], value["fr"] ].compact.uniq.join(" / ") : value.to_s
    end
  end
end
