class AddNeedsReviewToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :needs_review, :boolean, default: false, null: false
  end
end
