module PublicApi
  module V1
    # GET /v1, /v1/openapi.json, /v1/me and /v1/me/usage.
    class DiscoveryController < BaseController
      operation :index, :getIndex
      operation :openapi, :getOpenapi
      operation :me, :getMe
      operation :usage, :getUsage

      OPENAPI_CACHE = "public, max-age=300".freeze
      USAGE_RANGES = { "minute" => 24.hours, "hour" => 31.days, "day" => 400.days }.freeze

      def index
        latest = releases.last || AsOf.resolve(nil, releases:)
        data = {
          name: Spec.document.dig("info", "title"),
          version: Spec.version,
          latest_release: latest.number,
          links: {
            openapi: "/v1/openapi.json", docs: "https://data.buildcanada.com/docs", llms_txt: "https://data.buildcanada.com/llms.txt",
            mcp: "https://data.buildcanada.com/mcp", releases: "/v1/releases", datasets: "/v1/datasets", dictionary: "/v1/dictionary",
            search: "/v1/search?q={q}", entities: "/v1/entities", spending: "/v1/spending", exports: "/v1/exports"
          }
        }
        render_data({ data:, meta: meta(release: latest.number), links: { self: "/v1" } }, release: latest.number, pinned: false)
      end

      # The contract itself, as bundled (docs/openapi/dist/v1/openapi.json).
      # Served through this route, not the static file server, so it is
      # rate-limited like any operation and cached for 5 minutes, not a year.
      def openapi
        response.headers["Cache-Control"] = OPENAPI_CACHE
        finish_headers(200)
        send_file Spec::BUNDLE, type: "application/json", disposition: "inline"
      end

      def me
        c = current_api_caller
        used = @limiter&.enabled? ? @limiter.allowance_used(caller: c, ip: request.remote_ip) : 0
        # Behind the edge this limiter doesn't count; the rollup (usage_daily) does.
        used = [ used, c.account&.monthly_units_used.to_i ].max unless c.anonymous?
        plan = c.plan
        data = {
          authenticated: !c.anonymous?,
          account: c.account && { id: "acct_#{c.account.id}", name: c.account.name, kind: c.account.kind },
          key: c.api_key && { id: "key_#{c.api_key.id}", name: c.api_key.name, prefix: c.api_key.token_prefix, expires_at: Format.timestamp(c.api_key.expires_at) },
          oauth_client: oauth_client(c),
          plan: plan.name.start_with?("paid") ? "paid" : plan.name,
          scopes: c.scopes & %w[read:public read:persons usage:read keys:manage],
          limits: {
            rate_per_minute: plan.rate, burst: plan.burst, monthly_units: plan.daily ? nil : plan.monthly,
            daily_units: plan.daily, monthly_units_used: used
          }
        }
        latest = latest_release_or_nil
        render_data({ data:, meta: meta(release: latest, as_of: latest.to_s), links: { self: "/v1/me" } }, release: latest, pinned: false)
      end

      # Usage buckets (docs/public-interface-design.md §6.3), from
      # PublicApi::Usage.source: usage_daily for days, usage_hourly for hours
      # (7 days) and Analytics Engine for minutes. Caveats say when the rollup
      # is behind or a range is outside what is kept.
      def usage
        granularity = parameters["granularity"]
        to = parse_time("to") || Time.current.utc
        from = parse_time("from") || (granularity == "day" ? to - 30.days : to - 24.hours)
        if from >= to
          raise Problem.invalid(parameter: "from", detail: "Must be before `to`.")
        elsif to - from > USAGE_RANGES.fetch(granularity)
          raise Problem.invalid(parameter: "from", detail: "A #{granularity} range covers at most #{USAGE_RANGES.fetch(granularity).inspect}.")
        end

        source = Usage.source
        buckets = source.buckets(account: current_api_caller.account, granularity:, from:, to:, group_by: Array(parameters["group_by"]),
          limit: limit + 1, after: after)
        page, next_cursor = paginate(buckets, cursor_release: nil) { |b| [ b[:bucket_start], b[:key_id], b[:operation] ] }
        caveats = source.caveats(locale:, granularity:, from:, to:)
        render_data({
          data: page,
          meta: list_meta(next_cursor:, caveats:, release: nil, as_of: Format.timestamp(to)),
          links: page_links(next_cursor)
        }, release: nil, pinned: false)
      end

      private

      def latest_release_or_nil
        releases.last&.number
      rescue ActiveRecord::ActiveRecordError => e
        Rails.logger.warn("[public_api] /v1/me without a release: #{e.class}")
        nil
      end

      # Set once WS-F's OAuth callers reach this API (Keys::Caller#oauth_token).
      def oauth_client(caller)
        token = caller.respond_to?(:oauth_token) ? caller.oauth_token : nil
        app = token&.application
        app && { client_id: app.uid.to_s, name: app.name.to_s }
      end

      def parse_time(name)
        value = parameters[name] or return nil
        Time.iso8601(value).utc
      rescue ArgumentError
        raise Problem.invalid(parameter: name, detail: "Use an RFC 3339 timestamp, e.g. 2026-09-27T00:00:00Z.")
      end
    end
  end
end
