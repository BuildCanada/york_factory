class DropWarehouseAlerts < ActiveRecord::Migration[8.1]
  def up
    drop_table "warehouse.alert_events" if table_exists?("warehouse.alert_events")
    drop_table "warehouse.alerts" if table_exists?("warehouse.alerts")
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "legacy alert rows cannot be reconstructed after the saved-search cutover"
  end
end
