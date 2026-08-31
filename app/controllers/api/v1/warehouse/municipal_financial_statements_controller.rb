module Api
  module V1
    module Warehouse
      class MunicipalFinancialStatementsController < CmsBaseController
        PROVINCE_NAMES = {
          "ab" => "Alberta", "bc" => "British Columbia", "mb" => "Manitoba",
          "nb" => "New Brunswick", "nl" => "Newfoundland and Labrador",
          "ns" => "Nova Scotia", "nt" => "Northwest Territories", "nu" => "Nunavut",
          "on" => "Ontario", "pe" => "Prince Edward Island", "qc" => "Quebec",
          "sk" => "Saskatchewan", "yt" => "Yukon"
        }.freeze
        PROVINCE_SLUGS = PROVINCE_NAMES.transform_values { |name| name.parameterize }.freeze
        LOCAL_GOVERNMENT_LEVELS = %w[municipal regional provincial inuit other].freeze
        INDEX_PAGE_SIZE = 5_000
        SankeyItem = Data.define(:flow, :origin_flow, :category, :label, :value, :source_page, :position)

        def index
          page = [ params.fetch(:page, 1).to_i, 1 ].max
          per_page = params.fetch(:per_page, INDEX_PAGE_SIZE).to_i.clamp(1, INDEX_PAGE_SIZE)
          scope = latest_approved_extractions_scope
          canonical_ids, municipality_count, statement_count = paginated_municipality_ids(
            scope, page:, per_page:
          )
          statements = scope.where(institution_canonical_id: canonical_ids)
            .preload(:institution_release).to_a
          institutions = institutions_by_key(statements)

          data = statements.group_by(&:institution_canonical_id).filter_map do |canonical_id, extractions|
            institution = newest_institution(institutions, extractions, canonical_id)
            serialize_municipality(institution, extractions) if institution
          end

          sorted = data.sort_by { |row| [ row[:province], row[:name].downcase ] }
          render json: {
            data: sorted,
            meta: {
              municipality_count:, statement_count:,
              page:, per_page:, total_pages: (municipality_count.to_f / per_page).ceil
            }
          }
        end

        def show
          province = params[:province].to_s.downcase
          province = PROVINCE_SLUGS.key(province) || province
          canonical_id = "ca/#{province}/#{params[:municipality].to_s.gsub('--', '/')}"
          all_statements = latest_approved_extractions(canonical_id: canonical_id)
          statements = if params[:year].present?
            all_statements.select { |row| row.fiscal_year_end.year == params[:year].to_i }
          else
            all_statements
          end
          return render json: { error: "Not found" }, status: :not_found if statements.empty?

          institutions = institutions_by_key(all_statements)
          institution = newest_institution(institutions, all_statements, canonical_id)
          return render json: { error: "Not found" }, status: :not_found unless institution

          documents = documents_by_key(statements)
          facts = ::Warehouse::FinancialStatementFact
            .where(financial_statement_extraction_id: statements.map(&:id))
            .order(:concept)
            .group_by(&:financial_statement_extraction_id)
          line_items = ::Warehouse::FinancialStatementLineItem
            .where(financial_statement_extraction_id: statements.map(&:id))
            .order(:flow, :position)
            .group_by(&:financial_statement_extraction_id)
          context = context_for(institutions.values)

          render json: serialize_municipality(institution, all_statements).merge(
            context: context,
            statements: statements.sort_by(&:fiscal_year_end).reverse.map do |extraction|
              serialize_statement(extraction, documents:, facts:, line_items:, context:)
            end
          )
        end

        private

        # A document may be re-extracted or carried into a newer ontology release.
        # Publish one reviewed result per municipality and fiscal year, favouring the
        # newest release and then the most recently reviewed extraction.
        def latest_approved_extractions(canonical_id: nil)
          scope = latest_approved_extractions_scope
          scope = scope.where(institution_canonical_id: canonical_id) if canonical_id
          scope.preload(:institution_release).to_a
        end

        def latest_approved_extractions_scope
          ::Warehouse::FinancialStatementExtraction.publishable_details
            .joins(:institution_release)
            .joins(<<~SQL.squish)
              INNER JOIN warehouse.institutions municipal_institutions
                ON municipal_institutions.institution_release_id = warehouse.financial_statement_extractions.institution_release_id
                AND municipal_institutions.canonical_id = warehouse.financial_statement_extractions.institution_canonical_id
                AND municipal_institutions.government_level IN ('municipal', 'regional', 'provincial', 'inuit', 'other')
            SQL
            .select(<<~SQL.squish)
              DISTINCT ON (
                warehouse.financial_statement_extractions.institution_canonical_id,
                warehouse.financial_statement_extractions.fiscal_year_end
              ) warehouse.financial_statement_extractions.*
            SQL
            .order(Arel.sql(<<~SQL.squish))
              warehouse.financial_statement_extractions.institution_canonical_id,
              warehouse.financial_statement_extractions.fiscal_year_end,
              warehouse.institution_releases.effective_on DESC,
              warehouse.financial_statement_extractions.reviewed_at DESC NULLS LAST,
              warehouse.financial_statement_extractions.id DESC
            SQL
        end

        def paginated_municipality_ids(scope, page:, per_page:)
          connection = ::Warehouse::FinancialStatementExtraction.connection
          latest_sql = scope.to_sql
          statement_count = connection.select_value(<<~SQL.squish).to_i
            SELECT COUNT(*) FROM (#{latest_sql}) latest_financial_statements
          SQL
          municipality_count = connection.select_value(<<~SQL.squish).to_i
            SELECT COUNT(DISTINCT institution_canonical_id)
            FROM (#{latest_sql}) latest_financial_statements
          SQL
          offset = (page - 1) * per_page
          canonical_ids = connection.select_values(<<~SQL.squish)
            WITH latest_financial_statements AS (#{latest_sql})
            SELECT latest_financial_statements.institution_canonical_id
            FROM latest_financial_statements
            INNER JOIN warehouse.institutions index_institutions
              ON index_institutions.institution_release_id = latest_financial_statements.institution_release_id
              AND index_institutions.canonical_id = latest_financial_statements.institution_canonical_id
            GROUP BY latest_financial_statements.institution_canonical_id
            ORDER BY
              split_part(latest_financial_statements.institution_canonical_id, '/', 2),
              LOWER(MAX(COALESCE(index_institutions.name_en, index_institutions.name_fr, ''))),
              latest_financial_statements.institution_canonical_id
            LIMIT #{per_page} OFFSET #{offset}
          SQL
          [ canonical_ids, municipality_count, statement_count ]
        end

        def institutions_by_key(extractions)
          release_ids = extractions.map(&:institution_release_id).uniq
          canonical_ids = extractions.map(&:institution_canonical_id).uniq

          ::Warehouse::Institution.where(
            institution_release_id: release_ids,
            canonical_id: canonical_ids,
            government_level: LOCAL_GOVERNMENT_LEVELS
          ).index_by { |institution| [ institution.institution_release_id, institution.canonical_id ] }
        end

        def serialize_municipality(institution, extractions)
          segments = institution.canonical_id.split("/")
          province = segments.fetch(1)
          slug = segments.drop(2).join("--")
          {
            canonical_id: institution.canonical_id,
            slug: slug,
            province: province,
            province_name: PROVINCE_NAMES.fetch(province, province.upcase),
            province_slug: PROVINCE_SLUGS.fetch(province, province),
            name: display_name(institution.name_en.presence || institution.name_fr, province),
            name_fr: institution.name_fr,
            legal_form: institution.legal_form,
            website_url: institution.website_url,
            available_years: extractions.map { |row| row.fiscal_year_end.year }.uniq.sort.reverse,
            available_periods: extractions.map do |row|
              { year: row.fiscal_year_end.year, fiscal_year_end: row.fiscal_year_end }
            end.uniq.sort_by { _1[:fiscal_year_end] }.reverse
          }
        end

        def display_name(name, province)
          return name unless province.in?(%w[ab on])

          name.to_s
            .sub(/\A(?:The\s+)?City\s+of\s+/i, "")
            .sub(/,\s*City\s+of\z/i, "")
        end

        def newest_institution(institutions, extractions, canonical_id)
          newest = extractions.max_by do |row|
            [ row.institution_release.effective_on, row.reviewed_at || Time.at(0), row.id ]
          end
          institutions[[ newest.institution_release_id, canonical_id ]]
        end

        def documents_by_key(extractions)
          ::Warehouse::InstitutionDocument
            .where(
              institution_release_id: extractions.map(&:institution_release_id).uniq,
              canonical_id: extractions.map(&:document_canonical_id).uniq
            )
            .includes(:institution_document_assets)
            .index_by { |document| [ document.institution_release_id, document.canonical_id ] }
        end

        def serialize_statement(extraction, documents:, facts:, line_items:, context:)
          document = documents[[ extraction.institution_release_id, extraction.document_canonical_id ]]
          asset = document&.institution_document_assets&.find { |row| row.content_sha256 == extraction.asset_sha256 }
          extraction_facts = facts.fetch(extraction.id, [])
          extraction_line_items = line_items.fetch(extraction.id, [])

          {
            fiscal_year: extraction.fiscal_year_end.year,
            fiscal_year_end: extraction.fiscal_year_end,
            statement_basis: extraction.statement_basis,
            language: extraction.language,
            source: {
              document_id: extraction.document_canonical_id,
              page_url: document&.source_page_url,
              download_url: asset&.download_url || document&.download_url
            },
            facts: extraction_facts.map do |fact|
              {
                concept: fact.concept,
                value: fact.value.to_f,
                raw_label: fact.raw_label,
                raw_text: fact.raw_text,
                statement: fact.statement,
                source_page: fact.source_page,
                column_year: fact.column_year,
                confidence: fact.extraction_confidence&.to_f
              }
            end,
            line_items: extraction_line_items.map do |item|
              {
                flow: item.flow, category: item.category, label: item.label,
                value: item.value.to_f, raw_text: item.raw_text, scale: item.scale,
                source_page: item.source_page, column_year: item.column_year,
                position: item.position, confidence: item.extraction_confidence&.to_f
              }
            end,
            verification: serialize_verification(extraction),
            per_capita: per_capita(extraction_facts, context),
            sankey: sankey(extraction_facts, extraction_line_items, checks: extraction.check_results)
          }
        end

        def serialize_verification(extraction)
          checks = ::Warehouse::FinancialStatementExtraction.verification_checks(extraction.check_results)
          counts = checks.map { _1[:status] }.tally
          failed = checks.length - counts.fetch("pass", 0) - counts.fetch("skip", 0)

          {
            status: extraction.status,
            reviewed_at: extraction.reviewed_at&.iso8601,
            reviewed_by: extraction.reviewed_by,
            review_notes: extraction.review_notes,
            summary: {
              total: checks.length,
              pass: counts.fetch("pass", 0),
              skip: counts.fetch("skip", 0),
              fail: failed
            },
            checks:
          }
        end

        def context_for(institutions)
          links = ::Warehouse::InstitutionGeography
            .where(institution_id: institutions.map(&:id), role: %w[governs administers])
            .includes(:institution_geography_snapshot)
          snapshots = links.map(&:institution_geography_snapshot).uniq(&:id)
          profiles = ::Warehouse::CensusProfile
            .where(
              census_year: snapshots.map(&:census_year).uniq,
              geo_level: "csd",
              geo_uid: snapshots.map(&:geo_uid)
            )
            .order(retrieved_at: :asc, id: :asc)
            .index_by { |row| [ row.census_year, row.geo_uid ] }
          population_for = ->(snapshot) do
            profiles[[ snapshot.census_year, snapshot.geo_uid ]]&.population || snapshot.population
          end
          area_for = ->(snapshot) do
            profiles[[ snapshot.census_year, snapshot.geo_uid ]]&.area_sq_km || snapshot.area_sq_km
          end
          population = snapshots.sum { |row| population_for.call(row).to_i }
          area = snapshots.sum { |row| (area_for.call(row) || 0).to_d }
          {
            census_year: snapshots.map(&:census_year).compact.max,
            population: population.positive? ? population : nil,
            area_sq_km: area.positive? ? area.to_f : nil,
            population_density_per_sq_km: population.positive? && area.positive? ? (population / area).to_f : nil,
            geographies: snapshots.map do |row|
              { uid: row.geo_uid, name: row.name_en.presence || row.name_fr, population: population_for.call(row),
                area_sq_km: area_for.call(row)&.to_f }
            end
          }
        end

        def per_capita(facts, context)
          population = context[:population]
          return nil unless population&.positive?

          facts.to_h do |fact|
            [ fact.concept, (fact.value.to_d / population).round(2).to_f ]
          end
        end

        def sankey(facts, line_items, checks:)
          return nil if line_items.empty?

          revenue = facts.find { _1.concept == "total_revenue" }&.value&.to_d
          spending = facts.find { _1.concept == "total_expenses" }&.value&.to_d
          return nil unless revenue&.positive? && spending&.positive?
          return nil unless sankey_reconciles?("revenue", revenue, line_items, checks)
          return nil unless sankey_reconciles?("expense", spending, line_items, checks)

          revenue = line_items.select { _1.flow == "revenue" }.sum { _1.value.to_d }
          spending = line_items.select { _1.flow == "expense" }.sum { _1.value.to_d }
          chart_items = normalized_sankey_items(line_items)
          inflows = chart_items.select { _1.flow == "revenue" }.sum { _1.value.to_d }
          outflows = chart_items.select { _1.flow == "expense" }.sum { _1.value.to_d }

          {
            total: [ inflows, outflows ].max.to_f,
            revenue: revenue.to_f,
            spending: spending.to_f,
            revenue_data: sankey_root("revenue", "Inflows", chart_items),
            spending_data: sankey_root("expense", "Outflows", chart_items)
          }
        end

        def sankey_reconciles?(flow, headline, line_items, checks)
          rows = line_items.select { |item| item.flow == flow }
          return false if rows.empty?

          difference = rows.sum { _1.value.to_d } - headline
          return true if difference.abs <= [ headline.abs * BigDecimal("0.001"), BigDecimal("1") ].max

          Array(checks).any? do |check|
            check = check.stringify_keys
            check["id"] == "line_sum:#{flow}" && check["status"] == "pass"
          end
        end

        def normalized_sankey_items(line_items)
          line_items.filter_map do |item|
            value = item.value.to_d
            next if value.zero?

            destination_flow = item.flow
            category = item.category
            if value.negative?
              destination_flow = item.flow == "revenue" ? "expense" : "revenue"
              category = item.flow == "revenue" ? "Revenue offsets and losses" : "Expense recoveries"
            end
            SankeyItem.new(
              flow: destination_flow, origin_flow: item.flow, category:, label: item.label,
              value: value.abs, source_page: item.source_page, position: item.position
            )
          end
        end

        def sankey_root(flow, label, line_items)
          rows = line_items.select { |item| item.flow == flow && item.value.positive? }
          children = rows.group_by { sankey_category(_1) }.map do |category, items|
            {
              id: "#{flow}-#{category.parameterize}", displayName: category, name: category, amount: 0,
              children: items.map do |item|
                {
                  id: [ flow, item.origin_flow, category.parameterize, item.label.parameterize,
                    item.position ].join("-"),
                  displayName: item.label, name: item.label,
                  amount: item.value.to_f,
                  source_page: item.source_page
                }
              end
            }
          end
          { id: "#{flow}-root", displayName: label, name: label, amount: 0, children: }
        end

        def sankey_category(item)
          return item.category if item.category.present? && item.category != item.label

          label = item.label
          if item.flow == "revenue"
            case label
            when /tax|taxe|compensation tenant lieu de taxes/i then "Taxes"
            when /transfer|grant|subvention|transfert|partage|quote-part/i then "Transfers and grants"
            when /service|sale|user fee|tarif|droit|license|licence|permit/i then "Services and fees"
            else "Investment and other revenue"
            end
          else
            case label
            when /administration|general government|governance/i then "General government"
            when /police|fire|sécurité|security|protection/i then "Public safety"
            when /transport|road|transit|voirie|circulation/i then "Transportation"
            when /water|sewer|waste|environment|hygiène|eau|égout|environnement/i then "Environmental services"
            when /health|social|housing|santé|logement/i then "Health, social, and housing"
            when /recreation|culture|library|loisir|bibliothèque/i then "Recreation and culture"
            else "Other municipal services"
            end
          end
        end
      end
    end
  end
end
