class CreateDirectorAppointments < ActiveRecord::Migration[8.1]
  def change
    create_table :director_appointments do |t|
      t.references :corporate_entity, null: false, foreign_key: true
      t.references :corporate_director, null: false, foreign_key: true
      t.date :appointed_date
      t.date :ceased_date
      t.string :role
      t.timestamps
    end

    add_index :director_appointments, [:corporate_entity_id, :corporate_director_id],
      unique: true, name: "idx_appointments_entity_director"
  end
end
