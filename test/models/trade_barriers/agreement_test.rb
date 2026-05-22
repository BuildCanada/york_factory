require "test_helper"

class TradeBarriers::AgreementTest < ActiveSupport::TestCase
  setup do
    @theme = TradeBarriers::Theme.find_or_create_by!(name: "Goods")
    @jurisdiction = Warehouse::Jurisdiction.find_or_create_by!(code: "AB") do |j|
      j.name = "Alberta"
      j.level = "provincial"
    end
  end

  test "is invalid without title" do
    a = TradeBarriers::Agreement.new(theme: @theme, status: "awaiting_sponsorship")
    assert_not a.valid?
    assert a.errors[:title].any?
  end

  test "auto-generates a slug from title via friendly_id" do
    a = TradeBarriers::Agreement.create!(title: "Direct-to-Consumer Alcohol Sales", theme: @theme)
    assert_equal "direct-to-consumer-alcohol-sales", a.slug
  end

  test "destroys associated agreement_jurisdictions and histories on destroy" do
    a = TradeBarriers::Agreement.create!(title: "Test agreement", theme: @theme)
    aj = a.agreement_jurisdictions.create!(jurisdiction: @jurisdiction, status: "committed")
    aj.histories.create!(status: "aware", date_entered: Date.new(2024, 1, 1))
    a.histories.create!(status: "under_negotiation", date_entered: Date.new(2024, 6, 1))

    assert_difference -> { TradeBarriers::AgreementJurisdiction.count }, -1 do
      assert_difference -> { TradeBarriers::AgreementHistory.count }, -1 do
        assert_difference -> { TradeBarriers::JurisdictionHistory.count }, -1 do
          a.destroy
        end
      end
    end
  end
end
