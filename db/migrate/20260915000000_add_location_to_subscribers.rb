class AddLocationToSubscribers < ActiveRecord::Migration[8.1]
  def change
    # Derived from postal_code via ConstituencyService, so that a contact
    # reaches Customer.io with a city on it rather than a postal code the
    # campaign side has to decode.
    add_column :subscribers, :city, :string
    add_column :subscribers, :province, :string
  end
end
