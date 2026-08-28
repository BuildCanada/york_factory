ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

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
