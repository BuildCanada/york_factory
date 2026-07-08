module Api
  module V1
    module Kpis
      # Dashboard time series for one measure, grouped by jurisdiction
      # (country / aggregate). Serves the economy dashboard charts.
      #
      # GET /api/v1/kpis/series?measure=gdp-per-capita-ppp
      #   &jurisdictions=ca,united-states,g7   (optional, defaults to all with data)
      #   &from=2000&to=2025                   (optional year bounds)
      #
      # Unpaginated by design: a series response is bounded (~10 jurisdictions
      # x ~30 annual points). Data changes at most weekly, so responses carry
      # public HTTP caching headers.
      class SeriesController < BaseController
        def index
          measure = ::Warehouse::Measure.canonical.find_by!(slug: params[:measure])

          scope = ::Warehouse::MeasureFact
            .where(measure_id: measure.id, value_type: "actual", period_basis: "full_year")
            .where.not(jurisdiction_id: nil)
          scope = scope.where(measurement_year: params[:from].to_i..) if params[:from].present?
          scope = scope.where(measurement_year: ..params[:to].to_i) if params[:to].present?

          jurisdictions = requested_jurisdictions(scope)
          facts = scope.where(jurisdiction_id: jurisdictions.keys).order(:measurement_year).to_a

          return unless stale_response?(measure, facts)

          render json: {
            data: {
              measure: serialize_measure(measure),
              series: serialize_series(facts, jurisdictions)
            },
            meta: {
              source: serialize_source(facts),
              year_range: [ facts.first&.measurement_year, facts.last&.measurement_year ].compact
            }
          }
        end

        private

        def requested_jurisdictions(scope)
          jurisdictions = if params[:jurisdictions].present?
            ::Warehouse::Jurisdiction.where(slug: params[:jurisdictions].split(",").map(&:strip))
          else
            ::Warehouse::Jurisdiction.where(id: scope.select(:jurisdiction_id).distinct)
          end
          jurisdictions.index_by(&:id)
        end

        def stale_response?(measure, facts)
          expires_in 1.hour, public: true
          fresh_when(
            etag: [ measure.id, facts.size, facts.map(&:canonical_observation_id).max,
                    params[:jurisdictions], params[:from], params[:to] ],
            last_modified: facts.map(&:approved_at).compact.max,
            public: true
          )
          !performed?
        end

        def serialize_measure(measure)
          {
            slug: measure.slug,
            name: measure.canonical_name,
            description: measure.description,
            category: measure.category,
            frequency: measure.frequency,
            higher_is_bad: measure.higher_is_bad,
            unit: serialize_unit(measure.unit)
          }
        end

        def serialize_series(facts, jurisdictions)
          facts.group_by(&:jurisdiction_id).map do |jurisdiction_id, jurisdiction_facts|
            jurisdiction = jurisdictions.fetch(jurisdiction_id)
            {
              jurisdiction: {
                slug: jurisdiction.slug,
                code: jurisdiction.code,
                name: jurisdiction.name,
                level: jurisdiction.level
              },
              computed: jurisdiction.code == "G7",
              points: jurisdiction_facts.map do |fact|
                { year: fact.measurement_year, value: fact.value_numeric }
              end
            }
          end.sort_by { |series| series[:jurisdiction][:name] }
        end

        def serialize_source(facts)
          document_ids = facts.map(&:document_id).uniq
          source = ::Warehouse::Source
            .joins(raw_ingestions: :kpi_documents)
            .where(kpi_documents: { id: document_ids })
            .order("warehouse.raw_ingestions.fetched_at DESC")
            .first
          return nil if source.nil?

          { name: source.name, url: source.url, last_fetched_at: source.last_fetched_at }
        end
      end
    end
  end
end
