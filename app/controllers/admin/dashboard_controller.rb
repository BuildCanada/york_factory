module Admin
  class DashboardController < BaseController
    def index
      @sources = Source.all.map { |s|
        latest = s.raw_ingestions.order(fetched_at: :desc).first
        {
          name: s.name,
          url: s.url,
          last_fetched_at: s.last_fetched_at,
          latest_ingestion: latest ? { status: latest.status, id: latest.id } : nil
        }
      }

      @counts = {
        organizations: Organization.count,
        fiscal_authorities: FiscalAuthority.count,
        fiscal_expenditures: FiscalExpenditure.count,
        standard_objects: StandardObjectExpenditure.count,
        lineage_entries: LineageEntry.count,
        lobbyists: Lobbyist.count,
        lobbying_activities: LobbyingActivity.count
      }

      @low_confidence_count = LineageEntry.where("confidence < 0.8").where.not(confidence: nil).count

      @anomalies = begin
        SpendingDeviation.anomalous.limit(10).map { |d|
          {
            organization: d.organization.canonical_name,
            fiscal_year: d.fiscal_year,
            variance_pct: d.variance_pct
          }
        }
      rescue
        []
      end
    end

    def ingestions
      @ingestions = RawIngestion.includes(:source).order(fetched_at: :desc).limit(50)
    end

    def lineage_review
      @entries = LineageEntry.where("confidence < 0.8")
        .where.not(confidence: nil)
        .where(human_override: false)
        .order(confidence: :asc)
        .limit(50)
    end

    def webflow_sync
      WebflowSyncJob.perform_later
      redirect_to admin_root_path, notice: "Webflow sync queued. Check Jobs for progress."
    end
  end
end
