require "test_helper"

class Api::V1::Kpis::Admin::OrganizationsTest < ActionDispatch::IntegrationTest
  setup do
    @jurisdiction = Warehouse::Jurisdiction.find_or_create_by!(code: "ORG-#{SecureRandom.hex(2)}") do |j|
      j.name = "Org Test"
      j.slug = "org-test-#{SecureRandom.hex(2)}"
      j.level = "federal"
      j.fiscal_year_start_month = 4
      j.default_currency = "CAD"
    end
    @raw_token = Warehouse::ApiToken.issue!(name: "org-test-#{SecureRandom.hex(2)}", scopes: [ "kpis:write" ])
  end

  test "creates a new organization and returns created=true" do
    slug = "newdept-#{SecureRandom.hex(2)}"
    post "/api/v1/kpis/admin/organizations",
      params: { organization: {
        jurisdiction_slug: @jurisdiction.slug,
        slug: slug,
        canonical_name: "New Department",
        kind: "department",
        aliases: [ "ND", "Dept of New" ]
      } },
      headers: auth_headers, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert body["created"]
    assert_equal slug, body["slug"]

    org = Warehouse::Organization.find(body["id"])
    aliases = org.organization_aliases.pluck(:alias_name).sort
    assert_includes aliases, "ND"
    assert_includes aliases, "Dept of New"
    assert_includes aliases, "New Department"  # canonical auto-registered
  end

  test "idempotent on (jurisdiction_slug, slug): created=false on repeat" do
    slug = "idem-#{SecureRandom.hex(2)}"
    payload = { organization: {
      jurisdiction_slug: @jurisdiction.slug,
      slug: slug,
      canonical_name: "Idem Dept"
    } }

    post "/api/v1/kpis/admin/organizations", params: payload, headers: auth_headers, as: :json
    first_id = JSON.parse(response.body)["id"]

    post "/api/v1/kpis/admin/organizations", params: payload, headers: auth_headers, as: :json
    body = JSON.parse(response.body)
    refute body["created"]
    assert_equal first_id, body["id"]
  end

  test "adds new aliases on subsequent calls without duplicating" do
    slug = "alias-grow-#{SecureRandom.hex(2)}"
    post "/api/v1/kpis/admin/organizations",
      params: { organization: { jurisdiction_slug: @jurisdiction.slug, slug: slug,
                                canonical_name: "Alias Grow", aliases: [ "AG" ] } },
      headers: auth_headers, as: :json
    id = JSON.parse(response.body)["id"]

    post "/api/v1/kpis/admin/organizations",
      params: { organization: { jurisdiction_slug: @jurisdiction.slug, slug: slug,
                                canonical_name: "Alias Grow", aliases: [ "AG", "Alias-Grown" ] } },
      headers: auth_headers, as: :json
    aliases = Warehouse::Organization.find(id).organization_aliases.pluck(:alias_name).sort
    assert_equal [ "AG", "Alias Grow", "Alias-Grown" ], aliases
  end

  test "rejects unauthenticated requests" do
    post "/api/v1/kpis/admin/organizations",
      params: { organization: { jurisdiction_slug: @jurisdiction.slug, slug: "x", canonical_name: "x" } },
      as: :json
    assert_response :unauthorized
  end

  test "404 on unknown jurisdiction" do
    post "/api/v1/kpis/admin/organizations",
      params: { organization: { jurisdiction_slug: "no-such-#{SecureRandom.hex(2)}", slug: "x", canonical_name: "x" } },
      headers: auth_headers, as: :json
    assert_response :not_found
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@raw_token}" }
  end
end
