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
          }
        ]
      end
    end
  end
end
