module Admin
  class DashboardController < BaseController
    class_attribute :scrape_status, instance_accessor: false, default: Warehouse::Source::ScrapeStatus

    def index
      redirect_to admin_root_path
    end

    def scraping
      @scrape_states = self.class.scrape_status.active
      scrape_schedule = Warehouse::Source::ScrapeSchedule.new
      schedule_from = Time.current
      @scrape_batch_state = if @scrape_states.value?("running")
        "running"
      elsif @scrape_states.value?("queued")
        "queued"
      else
        "idle"
      end

      @sources = Warehouse::Source.order(:name).map { |s|
        latest = s.raw_ingestions.order(fetched_at: :desc).first
        {
          source: s,
          scrape_state: @scrape_states[s.id],
          next_scrape_at: scrape_schedule.next_run_at(s, from: schedule_from),
          scrape_schedule: scrape_schedule.schedule_for(s),
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

    def run_scrape
      source = Warehouse::Source.find(params[:id])
      if self.class.scrape_status.active.key?(source.id)
        return redirect_to admin_root_path, alert: "#{source.name} is already queued or running."
      end

      source.fetcher.fetch_later

      redirect_to admin_root_path, notice: "#{source.name} scrape queued."
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
  end
end
