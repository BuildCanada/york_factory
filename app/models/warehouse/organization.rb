class Warehouse::Organization < Warehouse::Record
  belongs_to :jurisdiction
  belongs_to :parent_organization, class_name: "Warehouse::Organization", optional: true

  has_many :child_organizations,
    class_name: "Warehouse::Organization",
    foreign_key: :parent_organization_id,
    inverse_of: :parent_organization,
    dependent: :nullify
  has_many :organization_aliases, dependent: :destroy
  has_many :fiscal_authorities, dependent: :destroy
  has_many :fiscal_expenditures, dependent: :destroy
  has_many :standard_object_expenditures, dependent: :destroy
  has_many :spending_awards, foreign_key: :payer_organization_id, dependent: :nullify
  has_many :lobbying_activities, dependent: :nullify
  has_many :measures, dependent: :restrict_with_error
  has_many :kpi_documents, dependent: :nullify
  has_many :predecessor_lineages,
    class_name: "Warehouse::OrganizationLineage",
    foreign_key: :successor_id,
    inverse_of: :successor,
    dependent: :destroy
  has_many :successor_lineages,
    class_name: "Warehouse::OrganizationLineage",
    foreign_key: :predecessor_id,
    inverse_of: :predecessor,
    dependent: :destroy

  has_object :entity_resolver

  before_validation :ensure_slug
  before_validation :ensure_jurisdiction

  validates :canonical_name, presence: true, uniqueness: { scope: :jurisdiction_id }
  validates :slug, presence: true, uniqueness: { scope: :jurisdiction_id }
  validates :org_id_infobase, uniqueness: true, allow_nil: true

  private

  def ensure_slug
    return if slug.present? || canonical_name.blank?
    self.slug = canonical_name.to_s.unicode_normalize(:nfkc).downcase
      .gsub(/[^a-z0-9]+/, "-").gsub(/(^-+|-+$)/, "").slice(0, 200)
  end

  def ensure_jurisdiction
    return if jurisdiction_id.present?
    self.jurisdiction_id = Warehouse::Jurisdiction.where(code: "CA").pick(:id)
  end
end
