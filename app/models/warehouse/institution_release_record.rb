module Warehouse::InstitutionReleaseRecord
  extend ActiveSupport::Concern

  included do
    belongs_to :institution_release, class_name: "Warehouse::InstitutionRelease"
    before_update :prevent_release_record_update
    before_destroy :prevent_release_record_destroy
  end

  private

  def prevent_release_record_update
    errors.add(:base, "ontology release records are append-only")
    throw :abort
  end

  def prevent_release_record_destroy
    errors.add(:base, "ontology release records are append-only")
    throw :abort
  end
end
