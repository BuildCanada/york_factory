module PublicApi
  module V1
    # The public data API, https://data.buildcanada.com/v1 (docs/public-interface-design.md
    # §3; the contract is docs/openapi/public/v1). Every action names its
    # operation in the contract, and the contract decides the rest: which
    # parameters are allowed and their schemas, the scopes, the request units
    # and the cache class. Each request:
    #
    # 1. gets a `req_<ULID>` ID (meta.request_id, a problem's instance);
    # 2. is authenticated by PublicApiAuthentication (a key, later an OAuth
    #    token, or anonymous with read:public);
    # 3. is charged its units by PublicApi::RateLimiter, unless the data-edge
    #    Worker signed it (the Worker limits and meters then);
    # 4. has its parameters checked against the contract (400 invalid_parameter);
    # 5. is answered in the `{data, meta, links}` envelope, with ETag and 304 for
    #    release-pinned data, or as an RFC 9457 problem.
    #
    # Every response says what it cost in BC-Usage-Units and BC-Operation (§5.5):
    # the operation's x-bc-units, 0 for a 304, 429 or 5xx, and 1 for other errors.
    class BaseController < ActionController::API
      include PublicApiAuthentication

      PINNED_CACHE = "public, max-age=31536000, immutable".freeze
      LATEST_CACHE = "public, max-age=300, stale-while-revalidate=3600".freeze
      SHORT_CACHE = "public, max-age=30".freeze
      PRIVATE_CACHE = "private, no-store".freeze
      UPGRADE_URL = Problem::UPGRADE_URL
      BULK_URL = Problem::BULK_URL

      class_attribute :operation_ids, instance_writer: false, default: {}

      # Names the contract operation an action implements.
      def self.operation(action, operation_id)
        self.operation_ids = operation_ids.merge(action.to_s => operation_id.to_s)
      end

      rescue_from StandardError, with: :render_unexpected
      rescue_from ActiveRecord::QueryCanceled, with: :render_statement_timeout
      rescue_from PublicApi::Problem, with: :render_problem

      before_action :start_request
      before_action :require_edge
      before_action -> { authenticate_public_api!(scopes: operation.scopes) }
      before_action :limit_rate
      before_action :parse_parameters

      private

      attr_reader :parameters

      def operation = @operation ||= Spec.operation(operation_ids.fetch(action_name))

      def start_request
        @request_id = RequestId.generate
        @units = operation.units_base
      end

      # In production the data-edge Worker fronts /v1 and signs what it
      # forwards (§2, "Origin protection"). PUBLIC_API_REQUIRE_EDGE=true refuses
      # anything else; until the Worker exists it is off, and Rails limits
      # requests itself.
      def require_edge
        return if internal_api_request? || edge_verified? || !ActiveModel::Type::Boolean.new.cast(ENV.fetch("PUBLIC_API_REQUIRE_EDGE", "false"))

        raise Problem.new(:unauthenticated, "Call the API at https://data.buildcanada.com/v1.")
      end

      def edge_verified?
        return @edge_verified if defined?(@edge_verified)

        @edge_verified = Edge::Signature.valid?(
          method: request.request_method, path: request.fullpath, body: "",
          timestamp: request.headers[Edge::Signature::TIMESTAMP_HEADER], signature: request.headers[Edge::Signature::SIGNATURE_HEADER]
        )
      end

      # The MCP server charges its own calls (Mcp::Meter), so an in-process
      # call from it is not charged twice.
      def limit_rate
        return if internal_api_request? || edge_verified?

        @limiter = RateLimiter.new
        return unless @limiter.enabled?

        @units = estimated_units
        @charge = @limiter.charge(caller: current_api_caller, ip: request.remote_ip, units: @units)
        @limit_result = @charge.result
        return if @limit_result.allowed

        @units = 0
        raise rate_problem(@limit_result)
      end

      # Units from the raw parameters, before they are validated (a page over
      # 50 or count=exact costs more; x-bc-units).
      def estimated_units
        limit = operation.parameter("limit") && params[:limit].to_s.match?(/\A\d+\z/) ? params[:limit].to_i : nil
        count = operation.parameter("count") && params[:count] == "exact"
        operation.units_for(limit:, count_exact: count)
      end

      def rate_problem(result) = Problem.rate_limited(result, caller: current_api_caller)

      def parse_parameters
        @parameters = Parameters.parse(operation, query: request.query_parameters, path: request.path_parameters.except(:controller, :action, :format))
      end

      # ---------- releases and as_of ----------

      def releases = FactFactory::ReleaseQuery.served

      # The release that answers: as_of, else the cursor's release, else the
      # latest. A cursor from another release than as_of is 409.
      def as_of
        @as_of ||= begin
          resolved = AsOf.resolve(parameters["as_of"], releases:)
          cursor = decoded_cursor
          if cursor&.release
            if parameters["as_of"].nil?
              resolved = AsOf.resolve(cursor.release.to_s, releases:)
            elsif cursor.release != resolved.release
              raise Problem.new(:release_mismatch,
                "This cursor belongs to release #{cursor.release}. Repeat with as_of=#{cursor.release}, or drop the cursor to start again.",
                cursor_release: cursor.release)
            end
          end
          resolved
        end
      end

      def release = as_of.release

      def latest_release = releases.last&.number

      def context = @context ||= Context.new(release:, locale:)

      def locale
        preferred = request.headers["Accept-Language"].to_s.split(",").first.to_s.strip.downcase
        preferred.start_with?("fr") ? "fr" : "en"
      end

      # ---------- pagination ----------

      def limit = parameters["limit"] || 50

      def decoded_cursor
        return @decoded_cursor if defined?(@decoded_cursor)

        @decoded_cursor = parameters["cursor"] && begin
          cursor = Cursor.decode(parameters["cursor"])
          unless cursor.fingerprint == cursor_fingerprint
            raise Problem.invalid(parameter: "cursor", detail: "This cursor belongs to a request with other parameters. Send it with the same parameters, or drop it.")
          end

          cursor
        rescue Cursor::Invalid => e
          raise Problem.invalid(parameter: "cursor", detail: "#{e.message.upcase_first}. Use the meta.next_cursor of the previous page.")
        end
      end

      # The cursor's sort key, for the query's keyset.
      def after = decoded_cursor&.keys

      # The parameters a cursor must be sent with again: everything but the
      # cursor, the page size and as_of (the cursor pins its release).
      def cursor_fingerprint
        Cursor.fingerprint(parameters.sent.except("cursor", "limit", "as_of").merge("_path" => request.path))
      end

      # [page, next cursor]: `rows` holds up to limit + 1 rows; `key` gives a
      # row's sort key.
      def paginate(rows, cursor_release: release, &key)
        page = rows.first(limit)
        next_cursor = if rows.size > limit
          Cursor.encode(release: cursor_release, keys: key.call(page.last), fingerprint: cursor_fingerprint)
        end
        [ page, next_cursor ]
      end

      # ---------- responses ----------

      def meta(caveats: [], release: self.release, as_of: release.to_s)
        { release:, as_of:, request_id: @request_id, caveats: caveats.uniq { |c| c[:code] } }
      end

      def list_meta(next_cursor:, count: nil, **options)
        meta(**options).merge(limit:, next_cursor:, count:)
      end

      # This request's parameters as sent, with as_of pinned last, for links.
      def self_link(pin: operation.parameter("as_of").present?, extra: {})
        sent = parameters.sent.except("as_of").merge(extra.transform_keys(&:to_s))
        sent["as_of"] = release if pin
        Links.url(request.path.chomp("/").presence || "/v1", sent)
      end

      def page_links(next_cursor, pin: operation.parameter("as_of").present?)
        {
          self: self_link(pin:),
          next: next_cursor && Links.url(request.path, parameters.sent.except("as_of", "cursor").merge(pin ? { "as_of" => release } : {}).merge("cursor" => next_cursor))
        }
      end

      # Renders `payload` (data, meta, links) as 200 with the operation's cache
      # rules: release data gets a strong ETag over everything but the request
      # ID, and If-None-Match answers 304.
      def render_data(payload, release: self.release, pinned: as_of_pinned?)
        cache = operation.cache
        headers = {}
        if cache == "release"
          etag = etag_for(payload, release)
          headers["ETag"] = etag
          headers["BC-Release"] = release.to_s
        end
        headers["Cache-Control"] = cache_control(cache, pinned:)
        if etag && etag_matches?(etag)
          @units = 0
          apply_headers(headers)
          return respond_with_status(:not_modified)
        end

        apply_headers(headers)
        respond_json(payload, status: :ok)
      end

      def as_of_pinned?
        return true if decoded_cursor&.release

        @as_of ? @as_of.pinned : false
      end

      def cache_control(cache, pinned:)
        return PRIVATE_CACHE if cache == "none" || parameters["count"] == "exact"
        return SHORT_CACHE if cache == "short"

        pinned ? PINNED_CACHE : LATEST_CACHE
      end

      def etag_for(payload, release)
        stable = payload.deep_dup
        stable[:meta] = stable[:meta].except(:request_id) if stable[:meta]
        %("r#{release}-#{OpenSSL::Digest::SHA256.hexdigest(JSON.generate([ locale, stable ]))[0, 12]}")
      end

      def etag_matches?(etag)
        header = request.headers["If-None-Match"].to_s
        return false if header.blank?
        return true if header.strip == "*"

        header.split(",").map { |t| t.strip.delete_prefix("W/") }.include?(etag)
      end

      def respond_json(payload, status:)
        finish_headers(status)
        render json: JSON.generate(payload), status:, content_type: "application/json"
      end

      def respond_with_status(status)
        finish_headers(status)
        head status
      end

      def apply_headers(headers) = headers.each { |k, v| response.headers[k] = v }

      # Headers every response carries, and the settled units.
      def finish_headers(status)
        code = Rack::Utils.status_code(status)
        units = if code == 304 then 0
        elsif code == 429 || code >= 500 then 0
        elsif code >= 300 then [ @units.to_i, 1 ].min
        else @units.to_i
        end
        if @charge
          rate_units = code == 304 ? 1 : units
          @limit_result = @limiter.settle(@charge, units:, rate_units:)
          @charge = nil
        end
        response.headers.merge!(@limit_result.headers) if @limit_result
        response.headers["BC-Usage-Units"] = units.to_s
        response.headers["BC-Operation"] = operation.id
        response.headers["BC-Request-Id"] = @request_id.to_s
        response.headers["Vary"] = "Accept-Language"
      end

      # ---------- problems ----------

      def render_problem(problem)
        @request_id ||= RequestId.generate
        problem.headers.each { |k, v| response.headers[k] = v }
        finish_headers(problem.status)
        render json: JSON.generate(problem.body(instance: @request_id)), status: problem.status, content_type: "application/problem+json"
      end

      # PublicApiAuthentication's failures, in this API's problem form.
      def render_api_problem(status:, code:, title:, detail:, **extra)
        problem = Problem.new(code, detail, title:, **extra)
        raise ArgumentError, "#{code} is #{problem.status}, not #{status}" unless problem.status == status

        render_problem(problem)
      end

      def render_statement_timeout(error)
        Rails.logger.warn("[public_api] statement timeout in #{operation.id}: #{error.message.lines.first}")
        render_problem(Problem.new(:query_too_broad, "The query took too long. Narrow it (filters, a smaller page), or use the bulk files at #{BULK_URL}."))
      end

      def render_unexpected(error)
        raise error if error.is_a?(Problem)

        Rails.error.report(error, handled: true, context: { request_id: @request_id, operation: operation_ids[action_name] })
        Rails.logger.error("[public_api] #{error.class}: #{error.message}\n#{Array(error.backtrace).first(10).join("\n")}")
        render_problem(Problem.new(:internal_error, "Something went wrong on our side. Quote #{@request_id ||= RequestId.generate} if it happens again."))
      end

      # `fields` (the Fields parameter): top-level fields of each item; id and
      # cite always stay. Unknown names are refused before any query.
      def check_fields!(allowed)
        unknown = Array(parameters["fields"]) - allowed
        return if unknown.empty?

        raise Problem.invalid(parameter: "fields", detail: "Unknown fields: #{unknown.join(', ')}. Choose from #{allowed.join(', ')}.")
      end

      def project(item)
        fields = parameters["fields"] or return item
        keep = (fields + %w[id cite]).map(&:to_sym)
        item.select { |key, _| keep.include?(key) }
      end

      # 404 for an ID nothing in the release has.
      def not_found!(what) = raise(Problem.not_found("No #{what} in release #{release}."))
    end
  end
end
