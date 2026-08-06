class AddSavedSearchDeliverySecretsAndPayloads < ActiveRecord::Migration[8.1]
  def change
    add_column :saved_searches, :webhook_secret, :string
    add_column :notification_batches, :payload, :jsonb, null: false, default: {}
  end
end
