module Admin
  class DashboardController < BaseController
    # Sources that can be triggered as background jobs
    INGESTABLE_SOURCES = %w[
      corporate_federal_ised corporate_bc_orgbook corporate_qc_req
      corporate_on_obr corporate_ab_cores corporate_sk_isc
      statcan_odbiz
    ].freeze

    def index
      @sources = Source.all.order(:name).map { |s|
        latest = s.raw_ingestions.order(fetched_at: :desc).first
        {
          name: s.name,
          url: s.url,
          format: s.format,
          last_fetched_at: s.last_fetched_at,
          latest_ingestion: latest ? { status: latest.status, id: latest.id } : nil,
          ingestable: INGESTABLE_SOURCES.include?(s.name) || s.name.start_with?("statcan_oda_")
        }
      }

      @counts = {
        government_entities: GovernmentEntity.count,
        fiscal_authorities: FiscalAuthority.count,
        fiscal_expenditures: FiscalExpenditure.count,
        corporate_entities: CorporateEntity.count,
        business_establishments: BusinessEstablishment.count,
        standardized_addresses: StandardizedAddress.count,
        lobbyists: Lobbyist.count,
        lobbying_activities: LobbyingActivity.count
      }

      @low_confidence_count = LineageEntry.where("confidence < 0.8").where.not(confidence: nil).count

      @anomalies = begin
        SpendingDeviation.anomalous.limit(10).map { |d|
          {
            government_entity: d.government_entity.canonical_name,
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

    def trigger_ingest
      source = Source.find_by!(name: params[:source_name])
      source.fetcher.fetch_later
      redirect_to admin_path, notice: "Queued ingestion for #{source.name}"
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_path, alert: "Source not found: #{params[:source_name]}"
    end

    def trigger_ingest_all
      triggered = []
      INGESTABLE_SOURCES.each do |name|
        source = Source.find_by(name: name)
        next unless source
        source.fetcher.fetch_later
        triggered << name
      end

      # Also trigger ODA sources
      Source.where("name LIKE 'statcan_oda_%'").find_each do |source|
        source.fetcher.fetch_later
        triggered << source.name
      end

      redirect_to admin_path, notice: "Queued #{triggered.size} ingestion jobs"
    end
  end
end
