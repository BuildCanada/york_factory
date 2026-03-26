class Testimonial < ApplicationRecord
  include Translatable, Publishable

  extend Mobility
  translates :quote, backend: :column

  has_one_attached :profile_photo
  has_one_attached :splash_photo

  validates :name, presence: true

  scope :ordered, -> { order(:position) }

  translatable_fields :quote
end
