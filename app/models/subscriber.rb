class Subscriber < ApplicationRecord
  # Vote pledges from the election tracker (rows cascade with the subscriber
  # in the DB).
  has_many :pledges_to_vote, class_name: "Warehouse::PledgeToVote"

  validates :email, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
end
