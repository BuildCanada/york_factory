ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
# Before rails/test_help: with eager loading (CI), it checks every model's
# table, the FactFactory ones included, so their database must exist and be
# loaded first.
require_relative "support/fact_factory_database"
require "rails/test_help"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |file| require file }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Rails gives each worker its own copy of every database, the hidden ones
    # included, by suffixing their names. The fact_factory database is loaded
    # once (support/fact_factory_database.rb) and only read: every worker uses it
    # under its own name.
    parallelize_setup do |worker|
      config = ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "fact_factory", include_hidden: true)
      config._database = config.database.delete_suffix("_#{worker}")
      FactFactoryRecord.connects_to database: { writing: :fact_factory, reading: :fact_factory }
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
