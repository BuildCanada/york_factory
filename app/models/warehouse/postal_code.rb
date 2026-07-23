class Warehouse::PostalCode < Warehouse::Record
  validates :postal_code, presence: true, uniqueness: true
  validates :latitude, :longitude, presence: true

  scope :in_province, ->(code) { where(province_code: code) }

  # Accepts "m4c1s9", "M4C 1S9", etc.; stored form is "M4C 1S9".
  def self.normalize(code)
    cleaned = code.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    return nil unless cleaned.match?(/\A[A-Z]\d[A-Z]\d[A-Z]\d\z/)

    "#{cleaned[0, 3]} #{cleaned[3, 3]}"
  end

  def self.lookup(code)
    normalized = normalize(code)
    normalized && find_by(postal_code: normalized)
  end
end
