require "test_helper"

class Warehouse::SourceTest < ActiveSupport::TestCase
  test "recognizes automatically scraped frequencies" do
    assert Warehouse::Source.new(fetch_frequency: "weekly").automatically_scraped?
    assert_not Warehouse::Source.new(fetch_frequency: "manual").automatically_scraped?
  end
end
