module Admin
  module Metrics
    class OverviewController < Admin::BaseController
      def index
        @sources = [
          {
            name: "Build Canada X",
            last_date: ::Metrics::TwitterStat.for_account("build_canada").maximum(:date),
            import_path: import_admin_metrics_twitter_stats_path,
            account_field: "build_canada",
            analytics_url: "https://x.com/i/account_analytics",
            accept: ".csv,.tsv,.txt",
            file_label: "CSV File"
          },
          {
            name: "Canada Spends X",
            last_date: ::Metrics::TwitterStat.for_account("canada_spends").maximum(:date),
            import_path: import_admin_metrics_twitter_stats_path,
            account_field: "canada_spends",
            analytics_url: "https://x.com/i/account_analytics",
            accept: ".csv,.tsv,.txt",
            file_label: "CSV File"
          },
          {
            name: "Build Toronto X",
            last_date: ::Metrics::TwitterStat.for_account("build_toronto").maximum(:date),
            import_path: import_admin_metrics_twitter_stats_path,
            account_field: "build_toronto",
            analytics_url: "https://x.com/i/account_analytics",
            accept: ".csv,.tsv,.txt",
            file_label: "CSV File"
          },
          {
            name: "Lucy Hargreaves X",
            last_date: ::Metrics::TwitterStat.for_account("lucyhargreaves4").maximum(:date),
            import_path: import_admin_metrics_twitter_stats_path,
            account_field: "lucyhargreaves4",
            analytics_url: "https://x.com/i/account_analytics",
            accept: ".csv,.tsv,.txt",
            file_label: "CSV File"
          },
          {
            name: "Build Canada Substack",
            last_date: ::Metrics::SubstackStat.for_account("build_canada").maximum(:date),
            import_path: import_admin_metrics_substack_stats_path,
            account_field: "build_canada",
            analytics_url: "https://buildcanada.substack.com/publish/stats/traffic",
            accept: ".csv",
            file_label: "CSV File"
          },
          {
            name: "Build Canada LinkedIn",
            last_date: ::Metrics::LinkedinStat.for_account("build_canada").maximum(:date),
            import_path: import_admin_metrics_linkedin_stats_path,
            account_field: "build_canada",
            analytics_url: "https://www.linkedin.com/company/105630886/admin/analytics/updates/",
            accept: ".xls,.xlsx",
            file_label: "XLS File"
          },
          {
            name: "Build Toronto LinkedIn",
            last_date: ::Metrics::LinkedinStat.for_account("build_toronto").maximum(:date),
            import_path: import_admin_metrics_linkedin_stats_path,
            account_field: "build_toronto",
            analytics_url: "https://www.linkedin.com/company/",
            accept: ".xls,.xlsx",
            file_label: "XLS File"
          },
          {
            name: "Build Canada TikTok",
            last_date: ::Metrics::TiktokStat.for_account("build_canada").maximum(:date),
            import_path: import_admin_metrics_tiktok_stats_path,
            account_field: "build_canada",
            analytics_url: "https://www.tiktok.com/tiktokstudio/analytics/overview",
            accept: ".csv,.zip",
            file_label: "CSV or ZIP"
          },
          {
            name: "Build Toronto TikTok",
            last_date: ::Metrics::TiktokStat.for_account("build_toronto").maximum(:date),
            import_path: import_admin_metrics_tiktok_stats_path,
            account_field: "build_toronto",
            analytics_url: "https://www.tiktok.com/tiktokstudio/analytics/overview",
            accept: ".csv,.zip",
            file_label: "CSV or ZIP"
          },
          {
            name: "Build Canada Instagram",
            last_date: ::Metrics::InstagramStat.for_account("build_canada").filled.maximum(:date),
            manual_path: new_admin_metrics_instagram_stat_path(account: "build_canada"),
            manage_path: admin_metrics_instagram_stats_path(account: "build_canada"),
            analytics_url: "https://business.instagram.com/",
            manual_note: "Weekly entry (Mon–Sun)"
          },
          meta_source("Build Toronto Instagram", "instagram", "build_toronto"),
          meta_source("Build Canada Facebook", "facebook", "build_canada"),
          meta_source("Build Toronto Facebook", "facebook", "build_toronto")
        ]
      end

      private

      def meta_source(name, platform, account_key)
        account = ::Metrics::MetaAccount.find_by(platform: platform, account_key: account_key)
        {
          name: name,
          last_date: account&.last_synced_at&.to_date,
          analytics_url: "https://business.facebook.com/",
          api_note: "Synced from the Meta Graph API"
        }
      end
    end
  end
end
