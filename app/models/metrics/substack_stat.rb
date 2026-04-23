module Metrics
  class SubstackStat < ApplicationRecord
    ACCOUNTS = %w[build_canada].freeze

    validates :account, presence: true, inclusion: { in: ACCOUNTS }
    validates :date, presence: true
    validates :date, uniqueness: { scope: :account }

    scope :for_account, ->(account) { where(account: account) }
    scope :recent_first, -> { order(date: :desc) }

    class << self
      def upsert_from_csv(account, csv_content)
        rows = parse_csv(csv_content)
        return { inserted: 0, updated: 0, errors: [ "No data rows found" ] } if rows.empty?

        inserted = 0
        updated = 0
        errors = []

        rows.each_with_index do |row, index|
          attrs = row.merge(account: account)
          record = find_or_initialize_by(account: account, date: attrs[:date])
          is_new = record.new_record?
          record.assign_attributes(attrs)

          if record.changed? || is_new
            if record.save
              is_new ? inserted += 1 : updated += 1
            else
              errors << "Row #{index + 1}: #{record.errors.full_messages.join(', ')}"
            end
          end
        rescue => e
          errors << "Row #{index + 1}: #{e.message}"
        end

        { inserted: inserted, updated: updated, errors: errors }
      end

      private

      def parse_csv(content)
        require "csv"

        content = content.encode("UTF-8", invalid: :replace, undef: :replace)
        content = content.sub(/\A\xEF\xBB\xBF/, "")

        parsed = CSV.parse(content, headers: true, liberal_parsing: true)

        parsed.filter_map do |row|
          date_val = row["Date"]
          next if date_val.blank?

          {
            date: Date.strptime(date_val, "%Y/%m/%d"),
            views: row["Views"].to_i
          }
        end
      end
    end
  end
end
