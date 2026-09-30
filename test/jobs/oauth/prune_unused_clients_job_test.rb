require "test_helper"

class Oauth::PruneUnusedClientsJobTest < ActiveJob::TestCase
  def client(created_at:, **attributes)
    Doorkeeper::Application.create!(name: "C", redirect_uri: "https://c.example/cb", confidential: false,
      client_type: "dynamic", created_at:, **attributes)
  end

  test "deletes week-old registrations that were never authorized" do
    stale = client(created_at: 8.days.ago)
    fresh = client(created_at: 1.day.ago)
    used = client(created_at: 8.days.ago)
    Doorkeeper::AccessToken.create!(application: used, resource_owner_id: users(:member).id, scopes: "read:public", expires_in: 60)
    reviewed = client(created_at: 8.days.ago, reviewed_at: Time.current)
    first_party = Doorkeeper::Application.create!(name: "TP", redirect_uri: "https://tp.example/cb", created_at: 30.days.ago)

    Oauth::PruneUnusedClientsJob.perform_now

    assert_not Doorkeeper::Application.exists?(stale.id)
    assert Doorkeeper::Application.exists?(fresh.id)
    assert Doorkeeper::Application.exists?(used.id)
    assert Doorkeeper::Application.exists?(reviewed.id)
    assert Doorkeeper::Application.exists?(first_party.id)
    assert_equal 1, AuditEvent.find_by!(action: "admin.oauth_clients_pruned").metadata["pruned"]
  end
end
