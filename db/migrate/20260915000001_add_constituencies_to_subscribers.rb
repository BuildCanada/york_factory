class AddConstituenciesToSubscribers < ActiveRecord::Migration[8.1]
  def change
    # Derived from postal_code alongside city and province, in the same
    # ConstituencyService response. Named to match hubspot_contacts rather
    # than "riding" so the two tables line up.
    add_column :subscribers, :federal_constituency, :string
    add_column :subscribers, :provincial_constituency, :string
  end
end
