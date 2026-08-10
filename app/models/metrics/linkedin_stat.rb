module Metrics
  class LinkedinStat < ApplicationRecord
    belongs_to :social_media_account,
      class_name: "Metrics::SocialMediaAccount",
      optional: true

    METRIC_COLUMNS = %w[
      impressions_organic impressions_sponsored impressions_total
      unique_impressions_organic
      clicks_organic clicks_sponsored clicks_total
      reactions_organic reactions_sponsored reactions_total
      comments_organic comments_sponsored comments_total
      reposts_organic reposts_sponsored reposts_total
    ].freeze

    RATE_COLUMNS = %w[
      engagement_rate_organic engagement_rate_sponsored engagement_rate_total
    ].freeze

    XLS_HEADER_MAP = {
      "Impressions (organic)" => :impressions_organic,
      "Impressions (sponsored)" => :impressions_sponsored,
      "Impressions (total)" => :impressions_total,
      "Unique impressions (organic)" => :unique_impressions_organic,
      "Clicks (organic)" => :clicks_organic,
      "Clicks (sponsored)" => :clicks_sponsored,
      "Clicks (total)" => :clicks_total,
      "Reactions (organic)" => :reactions_organic,
      "Reactions (sponsored)" => :reactions_sponsored,
      "Reactions (total)" => :reactions_total,
      "Comments (organic)" => :comments_organic,
      "Comments (sponsored)" => :comments_sponsored,
      "Comments (total)" => :comments_total,
      "Reposts (organic)" => :reposts_organic,
      "Reposts (sponsored)" => :reposts_sponsored,
      "Reposts (total)" => :reposts_total,
      "Engagement rate (organic)" => :engagement_rate_organic,
      "Engagement rate (sponsored)" => :engagement_rate_sponsored,
      "Engagement rate (total)" => :engagement_rate_total
    }.freeze

    ACCOUNTS = %w[build_canada].freeze

    validates :account, presence: true, inclusion: { in: ACCOUNTS }
    validates :date, presence: true
    validates :date, uniqueness: { scope: :account }

    scope :for_account, ->(account) { where(account: account) }
    scope :recent_first, -> { order(date: :desc) }

    class << self
      def upsert_from_xls(account, file)
        rows = parse_xls(file)
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

      def parse_xls(file)
        require "roo"
        require "roo-xls"

        spreadsheet = Roo::Spreadsheet.open(file, extension: :xls)
        sheet = spreadsheet.sheet("Metrics")

        # Row 1 = description, Row 2 = headers, Row 3+ = data
        headers = sheet.row(2)

        (3..sheet.last_row).filter_map do |row_num|
          row = sheet.row(row_num)
          date_val = row[0]
          next if date_val.blank?

          attrs = { date: Date.strptime(date_val.to_s, "%m/%d/%Y") }

          headers.each_with_index do |header, col_idx|
            next if col_idx == 0

            column = XLS_HEADER_MAP[header]
            next unless column

            value = row[col_idx]
            attrs[column] = if RATE_COLUMNS.include?(column.to_s)
              value.to_f
            else
              value.to_i
            end
          end

          attrs
        end
      end
    end
  end
end
