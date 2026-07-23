class AddPhotoFieldsToElectionCandidates < ActiveRecord::Migration[8.1]
  # The photo itself is an ActiveStorage attachment; these columns track
  # where it came from (manual upload vs an accepted suggestion), the
  # attribution line to display, and the machine-collected photo suggestions
  # (Wikipedia portrait, campaign-site og:image) awaiting admin review.
  def change
    add_column "warehouse.election_candidates", :photo_source, :string
    add_column "warehouse.election_candidates", :photo_attribution, :string
    add_column "warehouse.election_candidates", :photo_suggestions, :jsonb, null: false, default: []
  end
end
