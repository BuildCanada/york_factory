require "test_helper"
require "yabeda/post_hog"

class YabedaPostHogTest < ActiveSupport::TestCase
  setup do
    @payloads = []
    @client = Yabeda::PostHog::Client.new(
      api_key: "phc_test",
      host: "https://example.com",
      service_name: "york-factory",
      environment: "test",
      flush_interval: 3600,
      transport: ->(_uri, body) { @payloads << JSON.parse(body) }
    )
  end

  teardown do
    @client.shutdown
  end

  test "aggregates counters, gauges, and histograms into PostHog Metrics API payloads" do
    @client.count("activejob.executed_total", 2, attributes: { queue: "default" })
    @client.gauge("puma.pool_capacity", 3, attributes: { index: 0 })
    2.times { @client.histogram("rails.request_duration", 42, unit: "seconds", attributes: { status: 200 }) }

    @client.flush

    metrics = @payloads.fetch(0).dig("resourceMetrics", 0, "scopeMetrics", 0, "metrics")
    counter = metrics.find { |metric| metric["name"] == "activejob.executed_total" }
    gauge = metrics.find { |metric| metric["name"] == "puma.pool_capacity" }
    histogram = metrics.find { |metric| metric["name"] == "rails.request_duration" }

    assert_equal 2, counter.dig("sum", "dataPoints", 0, "asDouble")
    assert_equal 3, gauge.dig("gauge", "dataPoints", 0, "asDouble")
    assert_equal 2, histogram.dig("histogram", "dataPoints", 0, "count")
    assert_equal 84, histogram.dig("histogram", "dataPoints", 0, "sum")
  end
end
