require "json_schemer"

module PublicApi
  # The public data API's OpenAPI 3.1 contract (docs/openapi/public/v1, bundled
  # by bin/openapi-bundle), loaded once. The controllers read everything the
  # contract fixes from here rather than repeating it: each operation's
  # parameters and their schemas, its units (x-bc-units), scopes (x-bc-scopes)
  # and cache class (x-bc-cache). Tests validate responses against the same
  # document.
  class Spec
    BUNDLE = Rails.root.join("docs/openapi/dist/v1/openapi.json")

    Operation = Data.define(:id, :method, :path, :parameters, :units, :scopes, :cache, :responses) do
      def query_parameters = parameters.select { |p| p.location == "query" }

      def path_parameters = parameters.select { |p| p.location == "path" }

      def parameter(name) = parameters.find { |p| p.name == name }

      def paginated? = parameters.any? { |p| p.name == "cursor" }

      def status?(code) = responses.include?(code.to_s)

      # Units for one request (docs/public-interface-design.md §6.1, DECISIONS
      # 29): pages over 50 cost large_page instead of base; count=exact adds
      # count_exact.
      def units_for(limit: nil, count_exact: false)
        units = units_base
        units = self.units.fetch("large_page", units) if limit && limit > 50
        units += self.units.fetch("count_exact", 0) if count_exact
        units
      end

      def units_base = units.fetch("base")
    end

    # `schema` is the parameter's schema with a top-level $ref resolved.
    Parameter = Data.define(:name, :location, :required, :schema_pointer, :schema, :example) do
      def type = Array(schema["type"]).find { |t| t != "null" }

      def array? = type == "array"
    end

    class << self
      def instance
        @instance ||= new(JSON.parse(File.read(BUNDLE)))
      end

      delegate :operation, :operations, :document, :openapi, :version, :schema_at, to: :instance
    end

    attr_reader :document, :operations

    def initialize(document)
      @document = document
      @operations = build_operations.index_by(&:id)
    end

    def operation(id) = operations.fetch(id.to_s)

    def version = document.dig("info", "version")

    def openapi
      @openapi ||= JSONSchemer.openapi(document)
    end

    # A JSONSchemer schema for a JSON pointer into the document.
    def schema_at(pointer)
      @schemas ||= {}
      @schemas[pointer] ||= openapi.ref(pointer)
    end

    def self.pointer(*tokens)
      "#/" + tokens.map { |t| ERB::Util.url_encode(t.to_s.gsub("~", "~0").gsub("/", "~1")) }.join("/")
    end

    private

    def build_operations
      document.fetch("paths").flat_map do |path, item|
        %w[get].filter_map do |method|
          op = item[method] or next
          parameters = op.fetch("parameters", []).each_with_index.map { |param, index| build_parameter(path, method, param, index) }
          Operation.new(
            id: op.fetch("operationId"), method:, path:, parameters:,
            units: op.fetch("x-bc-units"), scopes: op.fetch("x-bc-scopes"), cache: op.fetch("x-bc-cache"),
            responses: op.fetch("responses").keys
          )
        end
      end
    end

    def build_parameter(path, method, param, index)
      pointer = if param["$ref"]
        param["$ref"]
      else
        self.class.pointer("paths", path, method, "parameters", index)
      end
      resolved = param["$ref"] ? resolve(param["$ref"]) : param
      Parameter.new(
        name: resolved.fetch("name"), location: resolved.fetch("in"), required: resolved.fetch("required", false),
        schema_pointer: "#{pointer}/schema", schema: resolve_schema(resolved.fetch("schema")), example: resolved["example"]
      )
    end

    def resolve_schema(schema)
      schema["$ref"] ? resolve_schema(resolve(schema["$ref"])) : schema
    end

    def resolve(ref)
      ref.delete_prefix("#/").split("/").reduce(document) { |node, token| node.fetch(token.gsub("~1", "/").gsub("~0", "~")) }
    end
  end
end
