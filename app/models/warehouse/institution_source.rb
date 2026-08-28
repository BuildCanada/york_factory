class Warehouse::InstitutionSource < Warehouse::Record
  include Warehouse::InstitutionReleaseRecord

  LANGUAGES = %w[en fr].freeze

  has_many :institutions, dependent: :restrict_with_error
  has_many :institution_identifiers, dependent: :restrict_with_error
  has_many :institution_relationships, dependent: :restrict_with_error
  has_many :institution_geographies, dependent: :restrict_with_error
  has_many :institution_documents, dependent: :restrict_with_error
  has_many :institution_coverages, dependent: :restrict_with_error

  validates :canonical_id,
    presence: true,
    uniqueness: { scope: :institution_release_id },
    format: { with: /\Aca\/sources\/[a-z0-9]+(?:-[a-z0-9]+)*(?:\/[a-z0-9]+(?:-[a-z0-9]+)*)*\z/ }
  validates :publisher_name, :url, :retrieved_at, presence: true
  validates :url, format: { with: /\Ahttps?:\/\/[^\s]+\z/ }
  validate :languages_are_supported

  private

  def languages_are_supported
    unsupported = Array(languages) - LANGUAGES
    errors.add(:languages, "contains unsupported values: #{unsupported.join(', ')}") if unsupported.any?
  end
end
