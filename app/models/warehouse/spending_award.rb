class Warehouse::SpendingAward < Warehouse::Record
  include Searchable
  searchable_in realm: "government_spending"

  AWARD_TYPES = %w[contract grant contribution transfer_payment].freeze
  STATES = %w[published withdrawn].freeze

  belongs_to :source
  belongs_to :raw_ingestion, optional: true
  belongs_to :payer_organization, class_name: "Warehouse::Organization", optional: true

  enum :state, { published: "published", withdrawn: "withdrawn" }

  scope :search_indexable, -> { published.where(is_canonical: true) }

  validates :external_key, :award_type, :state, :language, :title,
    :currency, :first_seen_at, :last_seen_at, :canonical_key, presence: true
  validates :external_key, uniqueness: { scope: :source_id }
  validates :award_type, inclusion: { in: AWARD_TYPES }
  validates :state, inclusion: { in: STATES }

  before_validation :set_canonical_key

  def search_data
    organization = payer_organization
    jurisdiction = organization&.jurisdiction

    {
      record_type: award_type,
      external_key: external_key,
      language: language,
      state: indexable_in_search? ? "published" : "withdrawn",
      published_at: occurred_at || first_seen_at,
      source_updated_at: updated_at,
      first_seen_at: first_seen_at,
      last_seen_at: last_seen_at,
      title: title,
      summary: description,
      content: [
        payer_name, recipient_name, program_name, description,
        searchable_metadata_text, amount, fiscal_year
      ].compact_blank.join(" — "),
      canonical_url: source_url,
      source_url: source_url || source.url,
      source_name: source.name,
      ontology: {
        "organization_ids" => Array(organization&.id),
        "organization_names" => Array(payer_name.presence || organization&.canonical_name),
        "jurisdiction_ids" => Array(jurisdiction&.id),
        "jurisdiction_codes" => Array(jurisdiction&.code),
        "jurisdiction_levels" => Array(jurisdiction&.level),
        "province_codes" => Array(province_code.presence),
        "country_codes" => Array(country_code.presence)
      },
      realm_data: {
        "external_key" => external_key,
        "award_type" => award_type,
        "payer_organization_ids" => Array(organization&.id),
        "payer_names" => Array(payer_name.presence || organization&.canonical_name),
        "recipient_name" => recipient_name,
        "program_name" => program_name,
        "program_key" => program_key,
        "fiscal_year" => fiscal_year,
        "occurred_at" => occurred_at,
        "amount" => amount&.to_f,
        "currency" => currency,
        "is_aggregated" => is_aggregated,
        "dataset_key" => source.name
      }.compact
    }
  end

  private

  def set_canonical_key
    self.canonical_key ||= external_key
  end

  def indexable_in_search?
    published? && is_canonical?
  end

  def searchable_metadata_text
    metadata.to_h.values.flatten.filter_map do |value|
      value.to_s if value.present? && !value.is_a?(Hash)
    end.join(" ")
  end
end
