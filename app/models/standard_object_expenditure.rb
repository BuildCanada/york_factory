class StandardObjectExpenditure < ApplicationRecord
  belongs_to :government_entity
  belongs_to :raw_ingestion, optional: true

  validates :fiscal_year, presence: true
  validates :standard_object, presence: true
end
