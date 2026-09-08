module Api
  module V1
    module Metrics
      class ImportsController < BaseController
        def twitter
          import!(
            platform: "twitter",
            accounts: ::Metrics::TwitterStat::ACCOUNTS,
            missing_file_message: "file must be an X analytics CSV or TSV"
          ) { |account, file| ::Metrics::TwitterStat.upsert_from_csv(account, file.read) }
        end

        def linkedin
          import!(
            platform: "linkedin",
            accounts: ::Metrics::LinkedinStat::ACCOUNTS,
            missing_file_message: "file must be a LinkedIn analytics XLS file"
          ) { |account, file| ::Metrics::LinkedinStat.upsert_from_xls(account, file.path) }
        end

        def tiktok
          import!(
            platform: "tiktok",
            accounts: ::Metrics::TiktokStat::ACCOUNTS,
            missing_file_message: "file must be a TikTok analytics CSV or ZIP"
          ) do |account, file|
            ::Metrics::TiktokStat.upsert_from_upload(
              account,
              file,
              start_year: params[:start_year].presence&.to_i
            )
          end
        end

        private

        def import!(platform:, accounts:, missing_file_message:)
          account = params[:account].to_s
          return render_invalid("account must be one of: #{accounts.join(', ')}") unless accounts.include?(account)

          file = params[:file]
          return render_invalid(missing_file_message) unless file.respond_to?(:read)

          result = yield(account, file)
          status = result[:inserted].zero? && result[:updated].zero? && result[:errors].any? ? :unprocessable_entity : :ok
          render json: result.merge(platform: platform, account: account), status: status
        rescue CSV::MalformedCSVError, Date::Error, Roo::Error, Zip::Error => error
          render_invalid(error.message)
        end

        def render_invalid(message)
          render json: { error: "invalid_upload", details: message }, status: :unprocessable_entity
        end
      end
    end
  end
end
