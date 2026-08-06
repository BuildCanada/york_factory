module Searchable
  extend ActiveSupport::Concern

  MODEL_NAMES = %w[
    Warehouse::MediaArticle
    Warehouse::SpendingAward
    Warehouse::FiscalExpenditure
    Warehouse::StandardObjectExpenditure
    Warehouse::Measure
  ].freeze

  class << self
    def models
      MODEL_NAMES.filter_map(&:safe_constantize)
    end

    def resolve(search_id)
      type, record_id = search_id.to_s.split(":", 2)
      return if type.blank? || record_id.blank?

      model = models.find { |candidate| candidate.search_type == type }
      model&.find_by(id: record_id)
    end

    def checkpoint
      models.filter_map { |model| model.search_synced.maximum(:search_index_sequence) }.max
    end

    def overlap_from_sequence(at: Time.current, window: 10.minutes)
      sequence = models.filter_map do |model|
        model.where(search_synced_at: (at - window)..).minimum(:search_index_sequence)
      end.min
      sequence ? [ sequence - 1, 0 ].max : nil
    end

    def record_count
      indexable_scopes.sum(&:count)
    end

    def pending_count
      indexable_scopes.sum { |scope| scope.where(search_synced_at: nil).count }
    end

    private

    def indexable_scopes
      models.map { |model| model.respond_to?(:search_indexable) ? model.search_indexable : model.all }
    end
  end

  included do
    class_attribute :search_realm, :search_record_type, :search_type, instance_writer: false
  end

  class_methods do
    def searchable_in(realm:, record_type: nil, as: nil)
      self.search_realm = realm.to_s
      self.search_record_type = record_type&.to_s
      self.search_type = (as || model_name.element).to_s
    end

    def search_synced
      where.not(search_synced_at: nil)
    end

    def find_by_search_id(search_id)
      type, record_id = search_id.to_s.split(":", 2)
      return unless type == search_type && record_id.present?

      find_by(id: record_id)
    end
  end

  def search_id
    raise ActiveRecord::RecordNotSaved, "searchable record must be persisted" unless persisted?

    "#{self.class.search_type}:#{id}"
  end

  def sync_to_search!(**options)
    perform_search_sync(**options)
  end

  def search_text
    search_embedding_text(normalized_search_attributes)
  end

  private

  def perform_search_sync(
    namespace: Search.turbopuffer_namespace,
    embedding_client: Search::Embedding::AzureCohereClient.new,
    input_builder: Search::Embedding::Input.new
  )
    attributes, sequence, revision, content_hash = prepare_search_sync!

    if withdrawn_from_search?(attributes)
      result = namespace.write(
        deletes: [ search_id ],
        delete_condition: [ "index_sequence", "Lte", sequence ],
        return_affected_ids: true
      )
      mark_search_synced!(sequence)
      return result
    end

    row = build_search_row(attributes, sequence:, revision:, content_hash:)
    prepared = input_builder.prepare(search_embedding_text(attributes))
    embedding_result = embedding_client.embed_documents([ prepared.text ])
    tokens = embedding_tokens(embedding_result.usage, prepared)
    row = Search::Schema.normalize_and_validate!(
      row.merge(
        embedding: embedding_result.vectors.fetch(0),
        embedding_model: embedding_result.model,
        embedding_scope: prepared.scope,
        embedding_input_tokens: tokens
      ),
      schema: Search::Schema.document,
      required: %i[realm record_type index_sequence search_revision search_content_hash embedding]
    )
    result = namespace.write(
      upsert_rows: [ row ],
      upsert_condition: [ "index_sequence", "Lt", { "$ref_new" => "index_sequence" } ],
      distance_metric: :cosine_distance,
      schema: Search::Schema.document,
      return_affected_ids: true
    )
    mark_search_synced!(
      sequence,
      search_embedding_model: row.fetch(:embedding_model),
      search_embedding_input_hash: prepared.hash,
      search_embedding_scope: prepared.scope,
      search_embedding_input_tokens: tokens
    )
    result
  end

  def prepare_search_sync!
    result = nil
    with_lock do
      attributes = normalized_search_attributes
      validate_search_attributes!(attributes)
      content_hash = search_realm_contract.content_hash(attributes)
      revision = if search_content_hash == content_hash
        [ search_revision.to_i, 1 ].max
      else
        search_revision.to_i + 1
      end
      sequence = self.class.connection.select_value(
        "SELECT nextval('search_index_sequence')"
      ).to_i
      update_columns(
        search_revision: revision,
        search_content_hash: content_hash,
        search_index_sequence: sequence,
        search_synced_at: nil,
        updated_at: Time.current
      )
      result = [ attributes, sequence, revision, content_hash ]
    end
    result
  end

  def normalized_search_attributes
    attributes = search_data.to_h.deep_symbolize_keys
    attributes[:realm] = self.class.search_realm.presence || attributes[:realm]
    attributes[:record_type] = self.class.search_record_type.presence || attributes[:record_type]
    attributes[:language] = attributes[:language].to_s.downcase.presence || "und"
    attributes[:visibility] = attributes[:visibility].to_s.presence || "public"
    attributes[:permission_ids] = Array(attributes[:permission_ids])
    attributes[:ontology] = attributes[:ontology].to_h
    attributes[:realm_data] = attributes[:realm_data].to_h
    attributes
  end

  def validate_search_attributes!(attributes)
    raise ArgumentError, "search realm is required" if attributes[:realm].blank?
    raise ArgumentError, "search record type is required" if attributes[:record_type].blank?
    unless Search::Realms.key?(attributes[:realm])
      raise ArgumentError, "unknown search realm #{attributes[:realm].inspect}"
    end

    messages = search_realm_contract.validate_document(attributes)
    return if messages.empty?

    messages.each { |message| errors.add(:base, "search data #{message}") }
    raise ActiveRecord::RecordInvalid, self
  end

  def build_search_row(attributes, sequence:, revision:, content_hash:)
    ontology = attributes[:ontology].to_h.stringify_keys
    text = [ attributes[:title], attributes[:summary], attributes[:content] ].compact_blank.join("\n\n")
    language = attributes[:language]
    row = {
      id: search_id,
      realm: attributes[:realm],
      record_type: attributes[:record_type],
      language: language,
      visibility: attributes[:visibility],
      permission_ids: attributes[:permission_ids],
      index_sequence: sequence,
      search_revision: revision,
      search_content_hash: content_hash,
      title: attributes[:title],
      title_en: language == "en" ? attributes[:title] : nil,
      content_en: language == "en" ? text : nil,
      title_fr: language == "fr" ? attributes[:title] : nil,
      content_fr: language == "fr" ? text : nil,
      summary: attributes[:summary],
      canonical_url: attributes[:canonical_url],
      source_url: attributes[:source_url],
      source_name: attributes[:source_name],
      source_domain: source_domain(attributes[:canonical_url]),
      published_at: attributes[:published_at],
      source_updated_at: attributes[:source_updated_at],
      first_seen_at: attributes[:first_seen_at],
      last_seen_at: attributes[:last_seen_at],
      jurisdiction_ids: Array(ontology["jurisdiction_ids"]),
      jurisdiction_codes: Array(ontology["jurisdiction_codes"]),
      jurisdiction_levels: Array(ontology["jurisdiction_levels"]),
      organization_ids: Array(ontology["organization_ids"]),
      organization_names: Array(ontology["organization_names"]),
      geo_boundary_ids: Array(ontology["geo_boundary_ids"]),
      province_codes: Array(ontology["province_codes"]),
      country_codes: Array(ontology["country_codes"]),
      tags: Array(ontology["tags"]),
      categories: Array(ontology["categories"]),
      embedding_model: search_embedding_model,
      embedding_scope: search_embedding_scope,
      embedding_input_tokens: search_embedding_input_tokens
    }.merge(attributes[:realm_data].to_h.deep_symbolize_keys).compact

    Search::Schema.normalize_and_validate!(
      row,
      schema: Search::Schema.document,
      required: %i[realm record_type index_sequence search_revision search_content_hash]
    )
  end

  def search_embedding_text(attributes)
    data = attributes[:realm_data].to_h
    structured = search_realm_contract.embedding_fields.filter_map do |field|
      data[field] || data[field.to_sym]
    end
    [ attributes[:title], *structured, attributes[:summary], attributes[:content] ].compact_blank.join("\n\n")
  end

  def search_realm_contract
    Search::Realms.fetch(self.class.search_realm)
  end

  def withdrawn_from_search?(attributes)
    attributes[:state].to_s == "withdrawn"
  end

  def mark_search_synced!(sequence, metadata = {})
    self.class.where(id: id, search_index_sequence: sequence).update_all(
      metadata.merge(search_synced_at: Time.current, updated_at: Time.current)
    )
    reload
  end

  def source_domain(url)
    URI.parse(url.to_s).host if url.present?
  rescue URI::InvalidURIError
    nil
  end

  def embedding_tokens(usage, prepared)
    usage["prompt_tokens"] || usage[:prompt_tokens] ||
      usage["input_tokens"] || usage[:input_tokens] ||
      usage["total_tokens"] || usage[:total_tokens] || prepared.estimated_tokens
  end
end
