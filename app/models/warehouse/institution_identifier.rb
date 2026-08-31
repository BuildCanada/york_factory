class Warehouse::InstitutionIdentifier < Warehouse::Record
  include Warehouse::InstitutionReleaseRecord

  belongs_to :institution
  belongs_to :institution_source, class_name: "Warehouse::InstitutionSource", optional: true

  validates :scheme,
    presence: true,
    format: { with: /\A[a-z0-9]+(?:[._-][a-z0-9]+)*\z/ }
  validates :value, presence: true, uniqueness: { scope: [ :institution_release_id, :scheme ] }
  validates :scheme,
    uniqueness: {
      scope: [ :institution_release_id, :institution_id ],
      conditions: -> { where(preferred: true) }
    },
    if: :preferred?
end
