require "test_helper"

class PollPublicationTest < ActiveSupport::TestCase
  test "a poll requires its survey and valid fieldwork dates" do
    poll = Poll.new(slug: "poll", title_en: "Poll", fieldwork_start: Date.new(2026, 9, 5), fieldwork_end: Date.new(2026, 9, 1))
    assert_not poll.valid?
    assert poll.errors[:survey_slug].any?
    assert poll.errors[:fieldwork_end].any?
  end

  test "survey scope is constrained" do
    poll = Poll.new(slug: "scope", title_en: "Poll", survey_slug: "survey", body_en: "Analysis")
    poll.survey_scope = "municipal"
    assert poll.valid?
    poll.survey_scope = "other"
    assert_not poll.valid?
    assert poll.errors[:survey_scope].any?
  end

  test "PDF downloads fall back to English and JSON is shared across locales" do
    poll = Poll.new(slug: "poll", title_en: "Poll", survey_slug: "survey", body_en: "Report")
    poll.analysis_pdf_en.attach(io: StringIO.new("%PDF-1.4 test"), filename: "analysis.pdf", content_type: "application/pdf", identify: false)
    poll.crosstabs_json.attach(io: StringIO.new("{}"), filename: "crosstabs.json", content_type: "application/json", identify: false)
    I18n.with_locale(:fr) do
      assert_equal({ "analysis_pdf" => "analysis_pdf_en", "crosstabs_json" => "crosstabs_json", "analysis_markdown" => "analysis_markdown" }, poll.poll_downloads)
    end
  end

  test "a French report PDF is preferred in French and English is the fallback" do
    poll = Poll.new(slug: "poll", title_en: "Poll", survey_slug: "survey")
    poll.report_pdf_en.attach(io: StringIO.new("%PDF-1.4 en"), filename: "en.pdf", content_type: "application/pdf", identify: false)
    I18n.with_locale(:fr) { assert_equal({ "analysis_pdf" => "report_pdf_en" }, poll.poll_downloads) }
    poll.report_pdf_fr.attach(io: StringIO.new("%PDF-1.4 fr"), filename: "fr.pdf", content_type: "application/pdf", identify: false)
    I18n.with_locale(:fr) { assert_equal({ "analysis_pdf" => "report_pdf_fr" }, poll.poll_downloads) }
  end

  test "rejects non PDF attachments and invalid sample sizes" do
    poll = Poll.new(slug: "poll", title_en: "Poll", survey_slug: "survey", sample_size: 0)
    poll.analysis_pdf_en.attach(io: StringIO.new("hello"), filename: "analysis.txt", content_type: "text/plain", identify: false)
    assert_not poll.valid?
    assert poll.errors[:analysis_pdf_en].any?
    assert poll.errors[:sample_size].any?
  end
end
