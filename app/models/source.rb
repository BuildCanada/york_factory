class Source < ApplicationRecord
  has_many :raw_ingestions, dependent: :destroy

  has_object :fetcher

  validates :name, presence: true, uniqueness: true
  validates :url, presence: true
  validates :format, presence: true
end
