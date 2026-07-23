class AddRawToIdentities < ActiveRecord::Migration[8.1]
  # Stores the full OAuth payload (the entire OmniAuth auth hash for LinkedIn,
  # the tokeninfo hash for Google) so nothing the provider returns is discarded.
  def change
    add_column :identities, :raw, :jsonb
  end
end
