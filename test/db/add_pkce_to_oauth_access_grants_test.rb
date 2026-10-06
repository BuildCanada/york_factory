require "test_helper"
require Rails.root.join("db/migrate/20261006000001_add_pkce_to_oauth_access_grants")

# The public-API OAuth migration adds the same columns; this one must be a
# no-op when they already exist, whichever order the two land in.
class AddPkceToOauthAccessGrantsTest < ActiveSupport::TestCase
  test "up is a no-op when the PKCE columns already exist" do
    connection = ActiveRecord::Base.connection
    assert connection.column_exists?(:oauth_access_grants, :code_challenge)
    assert connection.column_exists?(:oauth_access_grants, :code_challenge_method)

    ActiveRecord::Migration.suppress_messages { AddPkceToOauthAccessGrants.new.migrate(:up) }

    assert connection.column_exists?(:oauth_access_grants, :code_challenge)
  end

  test "up adds the columns when they are missing" do
    connection = ActiveRecord::Base.connection
    connection.remove_column :oauth_access_grants, :code_challenge_method
    connection.remove_column :oauth_access_grants, :code_challenge

    ActiveRecord::Migration.suppress_messages { AddPkceToOauthAccessGrants.new.migrate(:up) }

    assert connection.column_exists?(:oauth_access_grants, :code_challenge, :string)
    assert connection.column_exists?(:oauth_access_grants, :code_challenge_method, :string)
  end
end
