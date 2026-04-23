module Admin
  class DashboardController < BaseController
    def index
      @sources = Warehouse::Source.all.map { |s|
        latest = s.raw_ingestions.order(fetched_at: :desc).first
        {
          name: s.name,
          url: s.url,
          last_fetched_at: s.last_fetched_at,
          latest_ingestion: latest ? { status: latest.status, id: latest.id } : nil
        }
      }

      @counts = {
        organizations: Warehouse::Organization.count,
        fiscal_authorities: Warehouse::FiscalAuthority.count,
        fiscal_expenditures: Warehouse::FiscalExpenditure.count,
        standard_objects: Warehouse::StandardObjectExpenditure.count,
        lineage_entries: Warehouse::LineageEntry.count,
        lobbyists: Warehouse::Lobbyist.count,
        lobbying_activities: Warehouse::LobbyingActivity.count
      }

      @low_confidence_count = Warehouse::LineageEntry.where("confidence < 0.8").where.not(confidence: nil).count

      @anomalies = begin
        Warehouse::SpendingDeviation.anomalous.limit(10).map { |d|
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
      @ingestions = Warehouse::RawIngestion.includes(:source).order(fetched_at: :desc).limit(50)
    end

    def lineage_review
      @entries = Warehouse::LineageEntry.where("confidence < 0.8")
        .where.not(confidence: nil)
        .where(human_override: false)
        .order(confidence: :asc)
        .limit(50)
    end

    def webflow_sync
      WebflowSyncJob.perform_later
      redirect_to admin_root_path, notice: "Webflow sync queued. Check Jobs for progress."
    end

    def build_toronto_sync
      BuildTorontoSyncJob.perform_later
      redirect_to admin_root_path, notice: "BuildToronto sync queued. Check Jobs for progress."
    end
  end
end
