module Warehouse::Spending::Scrapers
  class Base
    PERSIST_BATCH_SIZE = 500

    Result = Data.define(:created, :updated, :unchanged, :withdrawn) do
      def total
        created + updated + unchanged
      end
    end

    PROVINCE_CODES = {
      "alberta" => "AB",
      "british columbia" => "BC",
      "manitoba" => "MB",
      "new brunswick" => "NB",
      "newfoundland and labrador" => "NL",
      "northwest territories" => "NT",
      "nova scotia" => "NS",
      "nunavut" => "NU",
      "ontario" => "ON",
      "prince edward island" => "PE",
      "quebec" => "QC",
      "québec" => "QC",
      "saskatchewan" => "SK",
      "yukon" => "YT"
    }.freeze

    MATERIAL_COLUMNS = %i[
      award_type state language title description payer_organization_id payer_name
      recipient_name recipient_type program_name program_key fiscal_year occurred_at
      amount currency is_aggregated source_url province_code country_code metadata
      canonical_key is_canonical
    ].freeze

    attr_reader :raw_ingestion, :source

    def initialize(raw_ingestion)
      @raw_ingestion = raw_ingestion
      @source = raw_ingestion.source
    end

    def load(payload, withdraw_missing: true, withdrawal_scope: nil)
      started_at = Time.current
      counts = { created: 0, updated: 0, unchanged: 0 }
      batch = []

      each_attributes(payload) do |attributes|
        batch << attributes
        persist_batch(batch, counts:, seen_at: started_at) if batch.size >= PERSIST_BATCH_SIZE
      end
      persist_batch(batch, counts:, seen_at: started_at)
      raise "Spending ingestion contained no records" if counts.values.sum.zero?

      withdrawn = withdraw_missing ? withdraw_missing_records!(started_at, withdrawal_scope) : 0
      finalize_records!
      raw_ingestion.update!(status: :complete, error_message: nil)
      Warehouse::SyncSpendingIngestionJob.perform_later(raw_ingestion)
      Result.new(**counts, withdrawn: withdrawn)
    rescue => error
      raw_ingestion.update!(status: :failed, error_message: error.message)
      raise
    end

    private

    def each_attributes(_payload)
      raise NotImplementedError
    end

    def finalize_records!
    end

    def mark_canonical_versions!(*order_clauses)
      connection = Warehouse::SpendingAward.connection
      source_id = connection.quote(source.id)

      connection.execute(<<~SQL.squish)
        WITH ranked AS (
          SELECT id,
            ROW_NUMBER() OVER (
              PARTITION BY canonical_key
              ORDER BY #{order_clauses.join(", ")}, id DESC
            ) = 1 AS is_canonical
          FROM warehouse.spending_awards
          WHERE source_id = #{source_id}
            AND state = 'published'
        ), changed AS (
          SELECT awards.id, ranked.is_canonical
          FROM warehouse.spending_awards awards
          INNER JOIN ranked ON ranked.id = awards.id
          WHERE awards.is_canonical IS DISTINCT FROM ranked.is_canonical
        )
        UPDATE warehouse.spending_awards awards
        SET is_canonical = changed.is_canonical,
            search_synced_at = NULL,
            updated_at = CURRENT_TIMESTAMP
        FROM changed
        WHERE awards.id = changed.id
      SQL
    end

    def each_csv(payload)
      content = if payload.respond_to?(:read)
        payload
      else
        text = payload.to_s.dup.force_encoding("UTF-8").scrub("")
        text.delete_prefix!("\uFEFF")
        text.gsub!("\r\n", "\n")
        StringIO.new(text)
      end
      csv = CSV.new(
        content,
        headers: true,
        liberal_parsing: true,
        row_sep: "\n",
        header_converters: ->(header) { header.to_s.delete_suffix("\r") }
      )
      csv.each { |row| yield row.to_h }
    end

    def persist(attributes, seen_at:)
      attributes = normalize_attributes(attributes)
      record = source.spending_awards.find_or_initialize_by(external_key: attributes.fetch(:external_key))
      new_record = record.new_record?
      record.assign_attributes(attributes.except(:external_key))
      record.first_seen_at ||= seen_at
      record.last_seen_at = seen_at
      record.raw_ingestion = raw_ingestion

      material_change = new_record || record.changes.keys.map(&:to_sym).intersect?(MATERIAL_COLUMNS)
      if material_change
        record.search_synced_at = nil
        record.save!
        new_record ? :created : :updated
      else
        record.update_columns(last_seen_at: seen_at, raw_ingestion_id: raw_ingestion.id, updated_at: Time.current)
        :unchanged
      end
    end

    def persist_batch(batch, counts:, seen_at:)
      return if batch.empty?

      Warehouse::SpendingAward.transaction do
        batch.each do |attributes|
          counts[persist(attributes, seen_at: seen_at)] += 1
        end
      end
      batch.clear
    end

    def normalize_attributes(attributes)
      attributes.to_h.symbolize_keys.tap do |value|
        value[:external_key] = value.fetch(:external_key).to_s
        value[:canonical_key] = value[:canonical_key].presence || value[:external_key]
        value[:title] = clean(value[:title]).presence || value[:external_key]
        value[:description] = clean(value[:description])
        value[:payer_name] = clean(value[:payer_name])
        value[:payer_organization_id] ||= payer_organization_id(value[:payer_name])
        value[:recipient_name] = clean(value[:recipient_name])
        value[:program_name] = clean(value[:program_name])
        value[:program_key] = clean(value[:program_key])
        value[:language] = value[:language].presence || "en"
        value[:state] = value[:state].presence || "published"
        value[:currency] = value[:currency].presence || "CAD"
        value[:metadata] = value[:metadata].to_h.compact
      end
    end

    def withdraw_missing_records!(started_at, withdrawal_scope)
      records = source.spending_awards.published.where("last_seen_at < ?", started_at)
      records = records.where(withdrawal_scope) if withdrawal_scope.present?
      records.update_all(
        state: "withdrawn",
        last_seen_at: started_at,
        raw_ingestion_id: raw_ingestion.id,
        search_synced_at: nil,
        updated_at: Time.current
      )
    end

    def clean(value)
      Array(value).compact.join("; ").then { |text| ActionView::Base.full_sanitizer.sanitize(text) }
        .squish.presence
    end

    def amount(value)
      return if value.blank?

      text = value.to_s.strip
      negative = text.start_with?("(") && text.end_with?(")")
      decimal = text.gsub(/[^\d.\-]/, "").presence&.to_d
      negative && decimal ? -decimal.abs : decimal
    end

    def fiscal_year(value)
      value.to_s[/\b(19|20)\d{2}\b/]&.to_i
    end

    def occurred_at(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def province_code(value)
      code = clean(value)
      return if code.blank?
      return code.upcase if PROVINCE_CODES.value?(code.upcase)

      PROVINCE_CODES[code.downcase]
    end

    def country_code(value)
      country = clean(value)
      return if country.blank?
      return country.upcase if country.match?(/\A[A-Za-z]{2}\z/)
      return "CA" if country.casecmp?("Canada")

      nil
    end

    def stable_key(*parts)
      Digest::SHA256.hexdigest(parts.flatten.map { |part| clean(part).to_s }.join("\u001F"))
    end

    def english(value)
      clean(value)&.split(" | ", 2)&.first
    end

    def payer_organization_id(name)
      return if name.blank?

      organization_ids_by_name[name.downcase]
    end

    def organization_ids_by_name
      @organization_ids_by_name ||= begin
        canonical = Warehouse::Organization.pluck(:canonical_name, :id)
        aliases = Warehouse::OrganizationAlias.pluck(:alias_name, :organization_id)
        (canonical + aliases).to_h { |name, id| [ name.downcase, id ] }
      end
    end
  end
end
