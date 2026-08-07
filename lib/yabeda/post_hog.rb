# frozen_string_literal: true

# A Yabeda adapter backed by PostHog's direct Metrics API. It uses the same
# `/i/v1/metrics` JSON API as PostHog's JavaScript and Node clients, without
# requiring an OpenTelemetry SDK or exporter.

require "json"
require "net/http"
require "uri"
require "yabeda"
require "yabeda/base_adapter"

module Yabeda
  module PostHog
    class Client
      FLUSH_INTERVAL_SECONDS = 10
      MAX_SERIES_PER_FLUSH = 1_000
      HISTOGRAM_BOUNDS = [ 0, 5, 10, 25, 50, 75, 100, 250, 500, 750, 1000, 2500, 5000, 7500, 10_000 ].freeze

      def initialize(api_key:, host:, service_name:, environment:, flush_interval: FLUSH_INTERVAL_SECONDS,
                     max_series: MAX_SERIES_PER_FLUSH, transport: nil)
        @uri = URI("#{host.delete_suffix("/")}/i/v1/metrics?token=#{URI.encode_uri_component(api_key)}")
        @resource_attributes = {
          "service.name" => service_name.to_s,
          "deployment.environment" => environment.to_s,
          "process.pid" => Process.pid.to_s,
          "telemetry.sdk.name" => "yabeda-posthog",
          "telemetry.sdk.version" => "1.0.0"
        }
        @flush_interval = flush_interval
        @max_series = max_series
        @transport = transport || method(:post)
        @mutex = Mutex.new
        @series = {}
        @dropped_series = false
        @running = true
        @pid = Process.pid
        start_worker
      end

      def count(name, value = 1, unit: nil, attributes: {})
        capture(:count, name, value, unit:, attributes:)
      end

      def gauge(name, value, unit: nil, attributes: {})
        capture(:gauge, name, value, unit:, attributes:)
      end

      def histogram(name, value, unit: nil, attributes: {})
        capture(:histogram, name, value, unit:, attributes:)
      end

      def flush
        ensure_worker!
        collect
        window = @mutex.synchronize do
          next if @series.empty?

          previous = @series
          @series = {}
          @dropped_series = false
          previous
        end
        return if window.nil?

        @transport.call(@uri, JSON.generate(payload(window)))
      rescue StandardError => error
        merge(window) if window
        warn "[PostHog] Metrics API export failed: #{error.class}: #{error.message}"
      end

      def shutdown
        ensure_worker!
        @running = false
        @worker&.kill
        flush
      end

      private

      def collect
        Yabeda.collect!
      rescue StandardError => error
        # A failed collector (for example, a briefly unavailable Puma control
        # socket) must not prevent the rest of the batch from being exported.
        warn "[PostHog] Metric collection failed: #{error.class}: #{error.message}"
      end

      def capture(type, name, value, unit:, attributes:)
        ensure_worker!
        return unless valid?(type, name, value)

        attributes = attributes.transform_keys(&:to_s).transform_values(&:to_s)
        key = JSON.generate([ type, name, unit, attributes.sort ])

        @mutex.synchronize do
          if !@series.key?(key) && @series.length >= @max_series
            warn "[PostHog] Metrics series limit reached (#{@max_series}); dropping new series" unless @dropped_series
            @dropped_series = true
            return
          end

          state = (@series[key] ||= new_state(type, name, unit, attributes))
          record(state, value)
        end
      end

      def valid?(type, name, value)
        type != :count || value >= 0 if name.is_a?(String) && !name.empty? && value.is_a?(Numeric) && value.finite?
      end

      def run
        while @running
          sleep @flush_interval
          flush if @running
        end
      end

      def start_worker
        @worker = Thread.new { run }
        @worker.abort_on_exception = false
      end

      # Puma forks workers after boot when WEB_CONCURRENCY is greater than one.
      # Threads do not survive fork, so each child gets its own exporter thread
      # and never exports samples collected in the pre-fork parent.
      def ensure_worker!
        return if @pid == Process.pid

        @mutex.synchronize do
          return if @pid == Process.pid

          @pid = Process.pid
          @resource_attributes["process.pid"] = @pid.to_s
          @series = {}
          @dropped_series = false
          @running = true
          start_worker
        end
      end

      def new_state(type, name, unit, attributes)
        { type:, name:, unit:, attributes:, started_at: Time.now, total: 0, count: 0,
          sum: 0, min: nil, max: nil, bucket_counts: Array.new(HISTOGRAM_BOUNDS.length + 1, 0) }
      end

      def record(state, value)
        case state[:type]
        when :count
          state[:total] += value
        when :gauge
          state[:last] = value
        when :histogram
          state[:count] += 1
          state[:sum] += value
          state[:min] = [ state[:min], value ].compact.min
          state[:max] = [ state[:max], value ].compact.max
          state[:bucket_counts][histogram_index(value)] += 1
        end
      end

      def merge(window)
        @mutex.synchronize do
          window.each do |key, state|
            current = @series[key]
            if current
              current[:started_at] = [ current[:started_at], state[:started_at] ].min
              merge_state(current, state)
            elsif @series.length < @max_series
              @series[key] = state
            end
          end
        end
      end

      def merge_state(current, previous)
        case current[:type]
        when :count
          current[:total] += previous[:total]
        when :histogram
          current[:count] += previous[:count]
          current[:sum] += previous[:sum]
          current[:min] = [ current[:min], previous[:min] ].compact.min
          current[:max] = [ current[:max], previous[:max] ].compact.max
          current[:bucket_counts].each_index { |index| current[:bucket_counts][index] += previous[:bucket_counts][index] }
        end
      end

      def payload(window)
        now = timestamp
        metrics = window.values.group_by { |state| [ state[:type], state[:name], state[:unit] ] }.map do |(type, name, unit), states|
          metric = { name: name }
          metric[:unit] = unit if unit
          metric[type == :count ? :sum : type] = metric_data(type, states, now)
          metric
        end

        {
          resourceMetrics: [ {
            resource: { attributes: otlp_attributes(@resource_attributes) },
            scopeMetrics: [ {
              scope: { name: "yabeda-posthog", version: "1.0.0" },
              metrics: metrics
            } ]
          } ]
        }
      end

      def metric_data(type, states, now)
        points = states.map { |state| data_point(type, state, now) }
        case type
        when :count then { aggregationTemporality: 1, isMonotonic: true, dataPoints: points }
        when :gauge then { dataPoints: points }
        when :histogram then { aggregationTemporality: 1, dataPoints: points }
        end
      end

      def data_point(type, state, now)
        point = { attributes: otlp_attributes(state[:attributes]), timeUnixNano: now }
        case type
        when :count
          point.merge(startTimeUnixNano: timestamp(state[:started_at]), asDouble: state[:total])
        when :gauge
          point.merge(asDouble: state[:last])
        when :histogram
          point.merge(
            startTimeUnixNano: timestamp(state[:started_at]), count: state[:count], sum: state[:sum],
            min: state[:min], max: state[:max],
            bucketCounts: state[:bucket_counts], explicitBounds: HISTOGRAM_BOUNDS
          )
        end
      end

      def histogram_index(value)
        HISTOGRAM_BOUNDS.index { |bound| value <= bound } || HISTOGRAM_BOUNDS.length
      end

      def otlp_attributes(attributes)
        attributes.map { |key, value| { key: key, value: { stringValue: value.to_s } } }
      end

      def timestamp(time = Time.now)
        "#{(time.to_r * 1_000_000_000).to_i}"
      end

      def post(uri, body)
        request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
        request.body = body
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 5) { |http| http.request(request) }
        raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      end
    end

    class Adapter < BaseAdapter
      def initialize(client)
        @client = client
      end

      def register_counter!(_metric); end
      def register_gauge!(_metric); end
      def register_histogram!(_metric); end
      def register_summary!(_metric); end

      def perform_counter_increment!(metric, tags, increment)
        @client.count(metric_name(metric), increment, unit: metric.unit&.to_s, attributes: tags)
      end

      def perform_gauge_set!(metric, tags, value)
        @client.gauge(metric_name(metric), value, unit: metric.unit&.to_s, attributes: tags)
      end

      def perform_histogram_measure!(metric, tags, value)
        @client.histogram(metric_name(metric), value, unit: metric.unit&.to_s, attributes: tags)
      end

      def perform_summary_observe!(metric, tags, value)
        perform_histogram_measure!(metric, tags, value)
      end

      def shutdown
        @client.shutdown
      end

      private

      def metric_name(metric)
        [ metric.group, metric.name ].compact.join(".")
      end
    end

    def self.install!(api_key:, host:, service_name:, environment:)
      return Yabeda.adapters[:posthog] if Yabeda.adapters.key?(:posthog)

      adapter = Adapter.new(Client.new(api_key:, host:, service_name:, environment:))
      Yabeda.register_adapter(:posthog, adapter)
      at_exit { adapter.shutdown }
      adapter
    end
  end
end
