module Metrics
  class TwitterStat < ApplicationRecord
    belongs_to :social_media_account,
      class_name: "Metrics::SocialMediaAccount",
      optional: true

    ACCOUNTS = %w[build_canada build_toronto canada_spends lucyhargreaves4].freeze
    METRIC_COLUMNS = %w[
      impressions likes engagements bookmarks shares new_follows unfollows
      replies reposts profile_visits create_post video_views media_views
    ].freeze

    CSV_HEADER_MAP = {
      "Date" => :date,
      "Impressions" => :impressions,
      "Likes" => :likes,
      "Engagements" => :engagements,
      "Bookmarks" => :bookmarks,
      "Shares" => :shares,
      "New follows" => :new_follows,
      "Unfollows" => :unfollows,
      "Replies" => :replies,
      "Reposts" => :reposts,
      "Profile visits" => :profile_visits,
      "Create Post" => :create_post,
      "Video views" => :video_views,
      "Media views" => :media_views
    }.freeze

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

        separator = content.lines.first&.include?("\t") ? "\t" : ","
        parsed = CSV.parse(content, headers: true, col_sep: separator, liberal_parsing: true)

        parsed.filter_map do |row|
          date_val = row["Date"]
          next if date_val.blank?

          attrs = { date: Date.parse(date_val) }
          CSV_HEADER_MAP.except("Date").each do |header, column|
            attrs[column] = row[header].to_i
          end
          attrs
        end
      end
    end
  end
end
