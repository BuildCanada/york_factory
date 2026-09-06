require "test_helper"

class PollPublicationTest < ActiveSupport::TestCase
  test "a poll requires its survey and valid fieldwork dates" do
    memo = Memo.new(slug: "poll", title_en: "Poll", content_kind: "poll", fieldwork_start: Date.new(2026, 9, 5), fieldwork_end: Date.new(2026, 9, 1))
    assert_not memo.valid?
    assert memo.errors[:survey_slug].any?
    assert memo.errors[:fieldwork_end].any?
  end

  test "PDF downloads fall back to English and JSON is shared across locales" do
    memo = Memo.new(slug: "poll", title_en: "Poll", content_kind: "poll", survey_slug: "survey")
    memo.analysis_pdf_en.attach(io: StringIO.new("%PDF-1.4 test"), filename: "analysis.pdf", content_type: "application/pdf", identify: false)
    memo.crosstabs_json.attach(io: StringIO.new("{}"), filename: "crosstabs.json", content_type: "application/json", identify: false)
    I18n.with_locale(:fr) do
      assert_equal({ "analysis_pdf" => "analysis_pdf_en", "crosstabs_json" => "crosstabs_json" }, memo.poll_downloads)
    end
  end

  test "rejects non PDF attachments and invalid sample sizes" do
    memo = Memo.new(slug: "poll", title_en: "Poll", content_kind: "poll", survey_slug: "survey", sample_size: 0)
    memo.analysis_pdf_en.attach(io: StringIO.new("hello"), filename: "analysis.txt", content_type: "text/plain", identify: false)
    assert_not memo.valid?
    assert memo.errors[:analysis_pdf_en].any?
    assert memo.errors[:sample_size].any?
  end
end
