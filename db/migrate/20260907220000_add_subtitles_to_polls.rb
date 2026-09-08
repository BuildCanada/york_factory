class AddSubtitlesToPolls < ActiveRecord::Migration[8.1]
  def change
    add_column :polls, :subtitle_en, :text
    add_column :polls, :subtitle_fr, :text
  end
end
