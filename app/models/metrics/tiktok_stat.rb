module Metrics
  class TiktokStat < ApplicationRecord
    belongs_to :social_media_account,
      class_name: "Warehouse::SocialMediaAccount",
      optional: true

    ACCOUNTS = %w[build_canada].freeze

    METRIC_COLUMNS = %w[video_views profile_views likes comments shares].freeze

    CSV_HEADER_MAP = {
      "Video Views" => :video_views,
      "Profile Views" => :profile_views,
      "Likes" => :likes,
      "Comments" => :comments,
      "Shares" => :shares
    }.freeze

    validates :account, presence: true, inclusion: { in: ACCOUNTS }
    validates :date, presence: true
    validates :date, uniqueness: { scope: :account }

    scope :for_account, ->(account) { where(account: account) }
    scope :recent_first, -> { order(date: :desc) }

    class << self
      def upsert_from_upload(account, uploaded_file, start_year: nil)
        content = extract_csv(uploaded_file)
        return { inserted: 0, updated: 0, errors: [ "No CSV content found in upload" ] } if content.blank?

        inferred_year = start_year || infer_start_year(uploaded_file) || Date.current.year
        upsert_from_csv(account, content, start_year: inferred_year)
      end

      def upsert_from_csv(account, csv_content, start_year: Date.current.year)
        rows, parse_errors = parse_csv(csv_content, start_year)
        if rows.empty?
          return { inserted: 0, updated: 0, errors: parse_errors.presence || [ "No data rows found" ] }
        end

        inserted = 0
        updated = 0
        errors = parse_errors

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

      def extract_csv(uploaded_file)
        filename = uploaded_file.respond_to?(:original_filename) ? uploaded_file.original_filename.to_s : uploaded_file.to_s

        if filename.downcase.end_with?(".zip")
          read_csv_from_zip(uploaded_file)
        else
          uploaded_file.respond_to?(:read) ? uploaded_file.read : File.read(uploaded_file)
        end
      end

      def read_csv_from_zip(uploaded_file)
        require "zip"

        path = uploaded_file.respond_to?(:path) ? uploaded_file.path : uploaded_file
        Zip::File.open(path) do |zip|
          entry = zip.find { |e| e.name.downcase.end_with?(".csv") }
          return nil unless entry

          entry.get_input_stream.read
        end
      end

      def infer_start_year(uploaded_file)
        filename = uploaded_file.respond_to?(:original_filename) ? uploaded_file.original_filename.to_s : ""
        match = filename.match(/(\d{4})-\d{2}-\d{2}/)
        match && match[1].to_i
      end

      def parse_csv(content, start_year)
        require "csv"

        content = normalize_encoding(content)

        begin
          parsed = CSV.parse(content, headers: true, liberal_parsing: true)
        rescue CSV::MalformedCSVError => e
          return [ [], [ "Malformed CSV: #{e.message}" ] ]
        end

        year = start_year
        previous_month = nil
        rows = []
        errors = []

        parsed.each_with_index do |row, index|
          date_str = row["Date"]
          next if date_str.blank?

          parsed_date = Date.strptime("#{date_str.strip} #{year}", "%B %d %Y")

          if previous_month && parsed_date.month < previous_month
            year += 1
            parsed_date = Date.strptime("#{date_str.strip} #{year}", "%B %d %Y")
          end

          previous_month = parsed_date.month

          attrs = { date: parsed_date }
          CSV_HEADER_MAP.each do |header, column|
            attrs[column] = parse_metric(row[header], header)
          end
          rows << attrs
        rescue ArgumentError => e
          errors << "Row #{index + 1}: #{e.message}"
        end

        [ rows, errors ]
      end

      # Reject unparseable metric values instead of letting to_i silently
      # coerce corrupted data (e.g. "1\xFF234".to_i => 1) into the table.
      def parse_metric(raw, header)
        Integer(raw.to_s.strip.delete(","), 10)
      rescue ArgumentError, TypeError
        raise ArgumentError, "invalid #{header} value: #{raw.inspect}"
      end

      def normalize_encoding(content)
        content = content.dup
        if content.encoding == Encoding::ASCII_8BIT
          content.force_encoding(Encoding::UTF_8)
        elsif content.encoding != Encoding::UTF_8
          content = content.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        end
        content = content.scrub unless content.valid_encoding?
        content.delete_prefix("\uFEFF")
      end
    end
  end
end
