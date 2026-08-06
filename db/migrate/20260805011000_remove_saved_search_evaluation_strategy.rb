class RemoveSavedSearchEvaluationStrategy < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :saved_searches, name: "saved_searches_evaluation_strategy"
    remove_column :saved_searches, :evaluation_strategy, :string,
      default: "new_tail", null: false
    remove_column :saved_searches, :last_state_evaluated_at, :timestamptz
  end
end
