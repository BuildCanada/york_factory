class AddArtifactErrorsToPolls < ActiveRecord::Migration[8.1]
  def change
    add_column :polls, :artifact_errors, :jsonb, default: {}, null: false
  end
end
