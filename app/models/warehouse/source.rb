class Warehouse::Source < Warehouse::Record
  has_many :raw_ingestions, dependent: :destroy
  has_many :spending_awards, dependent: :restrict_with_error

  has_object :fetcher

  validates :name, presence: true, uniqueness: true
  validates :url, presence: true
  validates :format, presence: true
end
