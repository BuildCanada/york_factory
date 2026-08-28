ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Parallel test databases are loaded from structure.sql. PostgreSQL does not dump
    # extension-owned spatial_ref_sys data, so seed the WGS84 row used by geography columns.
    parallelize_setup do
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO public.spatial_ref_sys (srid, auth_name, auth_srid, srtext, proj4text)
        VALUES (
          4326, 'EPSG', 4326,
          'GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4326"]]',
          '+proj=longlat +datum=WGS84 +no_defs '
        ) ON CONFLICT (srid) DO NOTHING
      SQL
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Federal Canada jurisdiction is referenced by default by Warehouse::Organization
    # (it's the default jurisdiction for federal-pipeline-created orgs). Ensure it
    # exists in every test database.
    setup do
      Warehouse::Jurisdiction.find_or_create_by!(code: "CA") do |j|
        j.name = "Canada"
        j.slug = "ca"
        j.level = "federal"
        j.fiscal_year_start_month = 4
        j.default_currency = "CAD"
      end
    end

    # Add more helper methods to be used by all tests here...
  end
end

module AdminTestHelper
  def sign_in_admin
    post user_session_path, params: { email: users(:admin).email, password: "password123" }
  end
end
