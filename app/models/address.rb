class Address < WarehouseRecord
  belongs_to :raw_ingestion, optional: true

  validates :oda_uid, presence: true, uniqueness: true

  scope :in_province, ->(code) { where(province_code: code) }
  scope :in_postal_code, ->(pc) { where(postal_code: pc) }
  scope :in_csd, ->(uid) { where(csd_uid: uid) }
  scope :search_street, ->(q) { where("street_name ILIKE ?", "%#{sanitize_sql_like(q)}%") }
  scope :search_city, ->(q) { where("city ILIKE ?", "%#{sanitize_sql_like(q)}%") }
end
