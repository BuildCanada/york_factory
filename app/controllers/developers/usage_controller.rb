module Developers
  # GET /developers/usage.csv: the account's usage by day, key and operation
  # (design §4.4, "Usage: by day, key and operation; CSV").
  class UsageController < BaseController
    DAYS = 90

    def show
      respond_to do |format|
        format.csv do
          send_data csv, filename: "buildcanada-api-usage-#{@account.id}-#{Time.current.utc.to_date.iso8601}.csv", type: "text/csv"
        end
      end
    end

    private

    def csv
      keys = @account.api_keys.pluck(:id, :name, :token_prefix).to_h { |id, name, prefix| [ id, [ name, prefix ] ] }
      rows = @account.usage_days.where(day: (Time.current.utc.to_date - (DAYS - 1))..).order(:day, :api_key_id, :operation)
      CSV.generate do |out|
        out << %w[day key_id key_name key_prefix operation requests units cache_hits errors_4xx errors_5xx throttled]
        rows.each do |r|
          name, prefix = keys[r.api_key_id]
          out << [ r.day.iso8601, r.api_key_id && "key_#{r.api_key_id}", name, prefix, r.operation, r.requests, r.units, r.cache_hits,
                   r.errors_4xx, r.errors_5xx, r.throttled ].map { |v| csv_safe(v) }
        end
      end
    end

    # Key names are user text: keep spreadsheet formulas out of the file.
    def csv_safe(value) = value.is_a?(String) && value.match?(/\A[=+\-@\t\r]/) ? "'#{value}" : value
  end
end
