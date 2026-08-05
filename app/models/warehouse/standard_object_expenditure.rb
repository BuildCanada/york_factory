class Warehouse::StandardObjectExpenditure < Warehouse::Record
  include Searchable
  searchable_in realm: "government_spending", record_type: "standard_object_expenditure"

  belongs_to :organization
  belongs_to :raw_ingestion, optional: true

  validates :fiscal_year, presence: true
  validates :standard_object, presence: true

  after_commit :enqueue_search_sync, on: %i[create update]

  def sync_to_search!(**index_options)
    super(**index_options)
  end

  def search_data
    jurisdiction = organization.jurisdiction
    {
      external_key: "standard-object-expenditure:#{id}",
      language: "und",
      published_at: created_at,
      source_updated_at: updated_at,
      title: "#{organization.canonical_name} — #{standard_object}",
      summary: "#{fiscal_year} standard-object expenditure",
      content: [ organization.canonical_name, standard_object, amount, fiscal_year ].compact.join(" — "),
      ontology: {
        "organization_ids" => [ organization.id ],
        "organization_names" => [ organization.canonical_name ],
        "jurisdiction_ids" => [ jurisdiction.id ],
        "jurisdiction_codes" => [ jurisdiction.code ],
        "jurisdiction_levels" => [ jurisdiction.level ]
      },
      realm_data: {
        "external_key" => "standard-object-expenditure:#{id}",
        "award_type" => "standard_object_expenditure",
        "payer_organization_ids" => [ organization.id ],
        "payer_names" => [ organization.canonical_name ],
        "program_name" => standard_object,
        "fiscal_year" => fiscal_year.to_s[/\d{4}/]&.to_i,
        "amount" => amount&.to_f,
        "currency" => jurisdiction.default_currency,
        "is_aggregated" => true,
        "dataset_key" => "standard_object_expenditures"
      }.compact
    }
  end

  private

  def enqueue_search_sync
    Search::SyncJob.perform_later(self)
  end
end
