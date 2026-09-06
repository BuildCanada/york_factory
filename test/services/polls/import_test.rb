require "test_helper"

class Polls::ImportTest < ActiveSupport::TestCase
  def bundle
    { "schemaVersion" => 1, "kind" => "buildcanada-poll-publication",
      "memo" => { "slug" => "imported-poll", "survey_slug" => "survey", "title_en" => "Poll", "body_en" => "## Analysis",
        "published_at" => 1.day.ago.iso8601, "publication" => "build_toronto", "featured" => true },
      "crosstabs" => { "schemaVersion" => 2, "survey" => { "slug" => "survey" }, "tables" => [] } }
  end

  test "imports a draft with crosstabs and ignores publication controls" do
    memo = Polls::Import.call(bundle)
    assert memo.poll?
    assert memo.draft?
    assert_equal "build_canada", memo.publication
    assert_not memo.featured?
    assert memo.crosstabs_json.attached?
    assert_equal 2, JSON.parse(memo.crosstabs_json.download)["schemaVersion"]
  end

  test "rejects mismatched survey data and unsupported versions" do
    invalid = bundle
    invalid["crosstabs"]["survey"]["slug"] = "wrong-survey"
    assert_raises(ArgumentError) { Polls::Import.call(invalid) }
    invalid = bundle.merge("schemaVersion" => 2)
    assert_raises(ArgumentError) { Polls::Import.call(invalid) }
  end

  test "a repeated import cannot overwrite an existing release" do
    Polls::Import.call(bundle)
    assert_raises(ActiveRecord::RecordInvalid) { Polls::Import.call(bundle) }
  end
end
