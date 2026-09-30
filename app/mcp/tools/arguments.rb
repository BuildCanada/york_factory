module Mcp
  module Tools
    # Input schema pieces shared by several tools, taken from the /v1
    # contract's parameters so a tool accepts exactly what REST accepts.
    module Arguments
      module_function

      def as_of(operation_id)
        Schemas.parameter(operation_id, "as_of", description:
          "Pin the answer to one data release: a release number (\"11\"), a date (\"2026-09-01\") or an RFC 3339 " \
          "timestamp. Omit it on the first call; every result names its release, so pass that number here on every " \
          "later call to keep one consistent snapshot, and state it in your answer.")
      end

      def entity_id(description)
        Schemas.parameter("listSpending", "payer", description:)
      end

      def cursor
        { "type" => "string", "maxLength" => 512,
          "description" => "The next_cursor of the previous result, to get the next page. Send the same other arguments with it." }
      end

      def sources(operation_id)
        Schemas.parameter(operation_id, "source", description:
          "Only these spending sources (source keys, e.g. proactive_grants). Call describe_data(\"spending semantics\") for the list.")
      end

      def fiscal_year(operation_id)
        Schemas.parameter(operation_id, "fiscal_year", description:
          "A federal fiscal year as YYYY-YY: \"2024-25\" is April 1, 2024 to March 31, 2025.")
      end

      # "/v1/entities/<id>" from a bare ID or its gid.
      def entity_path(id) = "/v1/entities/#{ERB::Util.url_encode(PublicApi::Format.bare_id(id, 'Entity'))}"

      # [path, params] of a relative /v1 URL (a redirect's Location).
      def split(url)
        uri = URI.parse(url)
        [ uri.path, Rack::Utils.parse_query(uri.query).transform_keys(&:to_sym) ]
      end
    end
  end
end
