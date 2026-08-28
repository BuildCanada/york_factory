class Warehouse::InstitutionCoverage < Warehouse::Record
  include Warehouse::InstitutionReleaseRecord
  SUBJECTS = %w[
    institutions websites geographies relationships financial-statements annual-reports
    statement-of-financial-information financial-data-return document-assets csd-inventory
    csd-authority-mapping
  ].freeze
  STATUSES = %w[complete partial not-searched not-found unavailable failed].freeze

  belongs_to :institution_source, class_name: "Warehouse::InstitutionSource", optional: true

  validates :scope_id, :subject, :status, :notes, presence: true
  validates :subject, inclusion: { in: SUBJECTS }
  validates :subject, uniqueness: { scope: [ :institution_release_id, :scope_id ] }
  validates :status, inclusion: { in: STATUSES }
  validate :source_belongs_to_release

  private

  def source_belongs_to_release
    return unless institution_source && institution_source.institution_release_id != institution_release_id

    errors.add(:institution_source, "must belong to the same release")
  end
end
