class Warehouse::Source < Warehouse::Record
  SCRAPE_INTERVALS = {
    "daily" => 1.day,
    "weekly" => 1.week,
    "monthly" => 1.month,
    "quarterly" => 3.months,
    "annual" => 1.year
  }.freeze

  has_many :raw_ingestions, dependent: :destroy
  has_many :spending_awards, dependent: :restrict_with_error

  has_object :fetcher

  validates :name, presence: true, uniqueness: true
  validates :url, presence: true
  validates :format, presence: true

  def automatically_scraped?
    SCRAPE_INTERVALS.key?(fetch_frequency)
  end
end
