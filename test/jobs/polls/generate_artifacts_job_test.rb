require "test_helper"

class Polls::GenerateArtifactsJobTest < ActiveJob::TestCase
  setup do
    @poll = Poll.create!(slug: "artifact-test", title_en: "Research", survey_slug: "survey", body_en: "Original report")
    clear_enqueued_jobs
  end

  test "saving markdown enqueues generation while invalid saves do not" do
    assert_enqueued_with(job: Polls::GenerateArtifactsJob, args: [ @poll.id ]) { @poll.update!(body_en: "Revised report") }
    clear_enqueued_jobs
    assert_no_enqueued_jobs(only: Polls::GenerateArtifactsJob) { @poll.update(sample_size: -1, body_en: "Invalid revision") }
  end

  test "attaching replaced crosstabs enqueues generation and invalidates Excel" do
    @poll.crosstabs_json.attach(io: StringIO.new('{"schemaVersion":2,"tables":[]}'), filename: "source.json", content_type: "application/json", identify: false)
    digest = @poll.artifact_digest("crosstabs_xlsx")
    @poll.crosstabs_xlsx.attach(io: StringIO.new("xlsx"), filename: "old.xlsx", content_type: PollArtifacts::XLSX_TYPE, identify: false, metadata: { source_digest: digest })
    clear_enqueued_jobs
    assert_enqueued_with(job: Polls::GenerateArtifactsJob, args: [ @poll.id ]) do
      @poll.crosstabs_json.attach(io: StringIO.new('{"schemaVersion":2,"tables":[],"updated":true}'), filename: "source.json", content_type: "application/json", identify: false)
    end
    assert_not @poll.reload.artifact_current?("crosstabs_xlsx")
  end

  test "generation attaches current output and repeated jobs skip rendering" do
    renderer = Object.new
    renderer.define_singleton_method(:render) { "%PDF-1.4 test" }
    with_renderer(renderer) { Polls::GenerateArtifactsJob.new.perform(@poll.id) }
    assert @poll.reload.artifact_current?("analysis_pdf_en")
    assert_empty @poll.artifact_errors
    assert_no_enqueued_jobs(only: Polls::GenerateArtifactsJob) { @poll.save! }
    with_renderer(->(*) { flunk "Current artifact rendered twice" }) do
      Polls::GenerateArtifactsJob.new.perform(@poll.id)
    end
    @poll.update!(title_en: "Renamed", published_at: Time.zone.parse("2026-09-06"))
    assert_not @poll.reload.artifact_current?("analysis_pdf_en")
    assert_equal "Build Canada - 2026-09-06 - Renamed - Report.pdf", @poll.download_filename("analysis_pdf_en")
  end

  test "a concurrent edit prevents an old job from attaching its output" do
    id = @poll.id
    renderer = Object.new
    renderer.define_singleton_method(:render) do
      Poll.find(id).update!(body_en: "Newer report")
      "%PDF-1.4 stale"
    end
    with_renderer(renderer) { Polls::GenerateArtifactsJob.new.perform(id) }
    assert_not @poll.reload.analysis_pdf_en.attached?
  end

  test "renderer errors are visible and do not make stale downloads current" do
    renderer = Object.new
    renderer.define_singleton_method(:render) { raise ArgumentError, "Invalid chart" }
    assert_raises(ArgumentError) do
      with_renderer(renderer) { Polls::GenerateArtifactsJob.new.perform(@poll.id) }
    end
    assert_equal "Invalid chart", @poll.reload.artifact_errors.dig("analysis_pdf_en", "message")
    assert_not @poll.artifact_current?("analysis_pdf_en")
  end
  private

  def with_renderer(renderer)
    original = Polls::AnalysisPdf.method(:new)
    Polls::AnalysisPdf.define_singleton_method(:new) { |*args| renderer.respond_to?(:call) ? renderer.call(*args) : renderer }
    yield
  ensure
    Polls::AnalysisPdf.define_singleton_method(:new, original)
  end
end
