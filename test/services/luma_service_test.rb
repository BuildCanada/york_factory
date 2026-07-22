require "test_helper"

class LumaServiceTest < ActiveSupport::TestCase
  def setup
    @service = LumaService.new("test-api-key")
  end

  test "should initialize with api key" do
    assert_equal "test-api-key", @service.instance_variable_get(:@api_key)
  end

  test "should raise error without api key" do
    credentials = Rails.application.credentials
    credentials.define_singleton_method(:dig) { |*_keys| nil }

    assert_raises(ArgumentError) do
      LumaService.new
    end
  ensure
    credentials.singleton_class.remove_method(:dig)
  end

  test "should use credentials api key when none provided" do
    credentials = Rails.application.credentials
    credentials.define_singleton_method(:dig) do |*keys|
      "creds-api-key" if keys == [ :luma, :api_key ]
    end

    service = LumaService.new

    assert_equal "creds-api-key", service.instance_variable_get(:@api_key)
  ensure
    credentials.singleton_class.remove_method(:dig)
  end
end
