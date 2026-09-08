module Polls
  class CrosstabsWorkbook
    VERSION = 7
    DEMOGRAPHIC_TITLES = JSON.parse(Rails.root.join("config/poll_demographic_titles.json").read).freeze

    def initialize(poll)
      @poll = poll
    end

    def render
      report = CrosstabsExport.new(@poll.crosstabs_json.download).render
      tables = report["tables"]
      # Dependent tables band a question by answers to the other questions. They
      # share the question's number so readers can move between the two sheets.
      question_numbers = tables.each_with_index.to_h { |table, index| [ table["id"], index + 1 ] }
      dependent_tables = Array(report["dependentTables"]).select { |table| table.is_a?(Hash) && table["columns"].is_a?(Array) && table["rows"].is_a?(Array) }
      dependent_sheets = dependent_tables.each_with_index.map do |table, index|
        number = question_numbers[table["id"]] || tables.size + index + 1
        { table: table, number: number, name: "Q#{number} by others", heading: "Question #{number} by other questions" }
      end
      groups = Array(report["breakdowns"]).index_by { |group| group["id"] }
      package = Axlsx::Package.new
      book = package.workbook
      book.escape_formulas = true
      styles = workbook_styles(book)
      book.add_worksheet(name: "Summary & Index") do |sheet|
        sheet.add_row [ "Build Canada\n#{@poll.title_en}" ], style: styles[:title], height: [ 80, text_height(@poll.title_en, 75) + 24 ].max
        sheet.merge_cells("A1:B1")
        sheet.add_row [ "Release date", @poll.published_at&.strftime("%B %-d, %Y") || "Draft" ], style: styles[:text], height: 28
        {
          "Survey population" => english(report.dig("weighting", "universe")),
          "Population benchmark" => english(report.dig("weighting", "benchmarkNote")),
          "Sample size" => report.dig("weighting", "unweightedResponses")
        }.each do |label, value|
          sheet.add_row [ label, value ], style: styles[:text], height: text_height(value, 90) if value.present?
        end
        reading = "Percentages are weighted and rounded to whole numbers. Cells marked Suppressed have fewer than 50 respondents or no reported sample size. Blank cells indicate unavailable results. Multiple selections can total more than 100%. Sample sizes vary by question and group. Unknown demographic categories are omitted; overall totals include all respondents."
        reading += " Sheets named \"by others\" break a question down by how respondents answered the other questions." if dependent_sheets.any?
        sheet.add_row [ "Reading the results", reading ], style: styles[:text], height: dependent_sheets.any? ? 96 : 80
        sheet.add_row []
        sheet.add_row [ "Question", "Select a question to view results" ], style: styles[:heading], height: 30
        tables.each_with_index do |table, index|
          sheet.add_row [ "Question #{index + 1}", english(table["question"]) ], style: [ styles[:link], styles[:text] ], height: text_height(english(table["question"]), 90)
          sheet.add_hyperlink location: "'Q#{index + 1}'!A1", ref: "A#{sheet.rows.size}", target: :internal
        end
        if dependent_sheets.any?
          sheet.add_row []
          sheet.add_row [ "By other questions", "Select a question to view it broken down by answers to the other questions" ], style: styles[:heading], height: 30
          dependent_sheets.each do |entry|
            sheet.add_row [ entry[:heading], english(entry[:table]["question"]) ], style: [ styles[:link], styles[:text] ], height: text_height(english(entry[:table]["question"]), 90)
            sheet.add_hyperlink location: "'#{entry[:name]}'!A1", ref: "A#{sheet.rows.size}", target: :internal
          end
        end
        sheet.column_widths 28, 100
        sheet.sheet_view.show_grid_lines = false
      end
      tables.each_with_index do |table, index|
        add_table_sheet(book, styles, groups, question_numbers, table, name: "Q#{index + 1}", heading: "Question #{index + 1}")
      end
      dependent_sheets.each do |entry|
        add_table_sheet(book, styles, groups, question_numbers, entry[:table], name: entry[:name], heading: entry[:heading])
      end
      errors = package.validate
      raise ArgumentError, "Invalid workbook: #{errors.map(&:message).join('; ').truncate(1000)}" if errors.any?
      package.to_stream.read
    end

    private

    def add_table_sheet(book, styles, groups, question_numbers, table, name:, heading:)
      book.add_worksheet(name: name) do |sheet|
        columns = table.fetch("columns").reject { |column| unknown_category?(column) }
        last_column = Axlsx.col_ref([ columns.size, 1 ].max)
        sheet.add_row [ "Back to summary & index" ], style: styles[:link], height: 26
        sheet.add_hyperlink location: "'Summary & Index'!A1", ref: "A1", target: :internal
        sheet.add_row [ "#{heading}\n#{bilingual(table["question"])}" ], style: styles[:title], height: text_height(bilingual(table["question"]), 35 + columns.size * 14) + 32
        sheet.merge_cells("A2:#{last_column}2")
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
        labels = columns.map do |column|
          group_data = groups[column["breakdownId"]]
          group = group_data&.fetch("kind", nil) == "overall" ? nil : (DEMOGRAPHIC_TITLES[column["breakdownId"]] || english(group_data&.fetch("label", nil)))
          # A banner that is itself a question carries its number so the column can be traced back to its own sheet.
          number = question_numbers[column["breakdownId"]]
          group = "Q#{number}: #{group}" if group.present? && group_data&.fetch("kind", nil) == "question" && number
          [ group.presence, english(column["label"]) ].compact.uniq.join("\n")
        end
        sheet.add_row [ "Answer / sample size", *labels ], style: styles[:heading], height: labels.map { |label| text_height(label, 20) }.max || 40
        freeze_row = sheet.rows.size
        add_result_rows(sheet, table, columns, styles)
        Array(table["arms"]).each_with_index do |arm, arm_index|
          sheet.add_row []
          arm_heading = "Version #{arm_index + 1}: #{bilingual(arm["question"])}"
          sheet.add_row [ arm_heading ], style: styles[:heading], height: text_height(arm_heading, 35 + columns.size * 14)
          sheet.merge_cells("A#{sheet.rows.size}:#{last_column}#{sheet.rows.size}")
          add_result_rows(sheet, arm, columns, styles)
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

    def add_result_rows(sheet, table, columns, styles)
      table.fetch("rows").each_with_index do |row, row_index|
        band = row_index.even? ? :even : :odd
        number_style = row["kind"] == "weighted-percent" ? styles[:percent][band] : styles[:number][band]
        values = columns.map do |column|
          Array(table["suppressedColumns"]).include?(column["key"]) ? "Suppressed" : row.fetch("values")[column["key"]]
        end
        label = bilingual(row["label"])
        sheet.add_row [ label, *values ], style: [ styles[band], *Array.new(values.size, number_style) ], height: text_height(label, 48)
      end
    end

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
      value.is_a?(Hash) ? value.values_at("en", "fr").compact_blank.uniq.join("\n") : value.to_s
    end

    def english(value)
      value.is_a?(Hash) ? value["en"].to_s : value.to_s
    end
  end
end
