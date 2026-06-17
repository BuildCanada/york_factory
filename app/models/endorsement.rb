class Endorsement < Engagement
  belongs_to :memo, counter_cache: :endorsements_count

  # Endorsements are auto-approved for now. The status column exists so we can
  # introduce bot moderation later without a migration; storing them as
  # approved keeps them visible if/when listings start filtering by status.
  after_initialize :default_to_approved, if: :new_record?

  after_commit :revalidate_memo, on: [ :create, :destroy ]

  private

  def default_to_approved
    self.status = :approved if status == "pending"
  end
end
