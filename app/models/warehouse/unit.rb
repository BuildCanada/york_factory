class Warehouse::Unit < Warehouse::Record
  KINDS = %w[absolute ratio rate qualitative].freeze
  BASE_UNITS = %w[
    ratio count dollars
    seconds minutes hours days
    meters kilometers square_meters hectares tonnes
    kwh mwh tco2e other
  ].freeze

  has_many :measures, dependent: :restrict_with_error

  validates :symbol, presence: true, uniqueness: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :base_unit, inclusion: { in: BASE_UNITS }, allow_nil: true
  validates :scale, presence: true, numericality: true

  validate :qualitative_has_no_base_unit
  validate :rate_has_denominator

  private

  def qualitative_has_no_base_unit
    qualitative = kind == "qualitative"
    return if qualitative == base_unit.nil?

    errors.add(:base_unit, qualitative ? "must be blank for qualitative" : "is required")
  end

  def rate_has_denominator
    rate = kind == "rate"
    return if rate == denominator_unit.present?

    errors.add(:denominator_unit, rate ? "is required for rate units" : "must be blank for non-rate units")
  end
end
