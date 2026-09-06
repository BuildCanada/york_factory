class AddSurveyScopeToPolls < ActiveRecord::Migration[8.1]
  def change
    add_column :polls, :survey_scope, :string, default: "national", null: false
    add_check_constraint :polls, "survey_scope IN ('national', 'provincial', 'municipal')", name: "polls_survey_scope"
  end
end
