require "test_helper"

class Polls::AnalysisPdfTest < ActiveSupport::TestCase
  test "report template includes fonts cover takeaways and sanitized markdown with chart images" do
    poll = Poll.new(slug: "report", survey_slug: "survey", survey_scope: "provincial", title_en: "Public opinion", published_at: Time.zone.local(2026, 8, 7), body_en: "## Findings\n\nA **clear** finding.\n\n```buildcanada-chart\n{\"definition\":{\"title\":\"Support\"}}\n```\n\n<script>alert(1)</script>", methodology_en: "## Survey design\n\nWe surveyed Canadian adults.", key_messages_en: [ "First finding" ])
    renderer = Polls::AnalysisPdf.new(poll, "en")
    renderer.define_singleton_method(:render_chart) { |_| '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>' }
    html = renderer.document_html
    doc = Nokogiri::HTML(html)
    assert_equal "Public opinion", doc.at_css(".cover h1").text
    assert_equal "August 7, 2026", doc.at_css(".cover-date").text
    assert_equal "Public opinion Provincial poll August 7, 2026", doc.at_css(".cover").text.squish
    assert_includes html, renderer.send(:css_string, "www.buildcanada.com/polls/report")
    assert_includes doc.at_css(".takeaways").text, "First finding"
    assert_includes doc.at_css("main").text, "A clear finding."
    assert doc.at_css("main figure img")["src"].start_with?("data:image/svg+xml;base64,")
    assert_includes doc.css("body > section")[1].text, "We surveyed Canadian adults."
    assert_equal "section analysis", doc.css("body > section")[2]["class"]
    assert_empty doc.css("script")
    assert_includes html, "data:font/woff2;base64,"
    assert_not_includes doc.at_css("main").text, '"definition"'
  end
end
