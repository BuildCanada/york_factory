module Mcp
  # JSON Schemas for the tools, generated from the /v1 OpenAPI 3.1 contract
  # (PublicApi::Spec), so a tool's input and output can't drift from the REST
  # operation it wraps (docs/public-interface-design.md §7.1).
  #
  # OpenAPI 3.1 schemas are JSON Schema 2020-12 plus annotations; this keeps
  # the keywords (and the top-level descriptions), drops `example(s)` and `x-bc-*`, and
  # rewrites `#/components/schemas/X` to `#/$defs/X`, collecting every schema
  # referenced into the document's `$defs` (MCP allows only same-document
  # references).
  module Schemas
    DROP = %w[example examples].freeze

    module_function

    # A self-contained schema for a tool result: an object with `properties`
    # (each may reference components with ref("Name")) and `required`, plus
    # the ToolError alternative every tool can return instead.
    def output(properties:, required:, description: nil)
      success = { "type" => "object", "properties" => properties, "required" => required }
      success["description"] = description if description
      document = {
        "type" => "object",
        "anyOf" => [ success, { "$ref" => "#/$defs/ToolError" } ],
        "$defs" => { "ToolError" => tool_error }
      }
      collect_defs(document)
      document
    end

    def ref(name) = { "$ref" => "#/$defs/#{name}" }

    # A /v1 query parameter's schema, resolved and inlined, for a tool's input.
    def parameter(operation_id, name, description:, **overrides)
      param = PublicApi::Spec.operation(operation_id).parameter(name) or raise ArgumentError, "#{operation_id} has no #{name}"
      schema = inline(clean(param.schema))
      schema.except("title").merge("description" => description).merge(overrides.transform_keys(&:to_s)).compact
    end

    # What every tool returns instead of its result when it fails: the /v1
    # problem (RFC 9457 members), so an agent can branch on error.code.
    def tool_error
      {
        "type" => "object",
        "description" => "The tool failed. error is the Build Canada problem: branch on error.code " \
                         "(insufficient_scope, not_found, invalid_parameter, query_too_broad, rate_limited, quota_exceeded, ...).",
        "required" => [ "error" ],
        "properties" => {
          "error" => {
            "type" => "object",
            "required" => %w[code title detail],
            "properties" => {
              "code" => { "type" => "string" },
              "title" => { "type" => "string" },
              "status" => { "type" => "integer" },
              "detail" => { "type" => "string" },
              "type" => { "type" => "string" },
              "required_scope" => { "type" => "string" },
              "retry_after_seconds" => { "type" => "integer" },
              "docs" => { "type" => "string" }
            }
          }
        }
      }
    end

    def component(name) = PublicApi::Spec.document.dig("components", "schemas", name) || raise(KeyError, "no component #{name}")

    # Adds every component `document` references, transitively, to its $defs.
    def collect_defs(document)
      pending = refs_in(document)
      until pending.empty?
        name = pending.shift
        next if document["$defs"].key?(name)

        document["$defs"][name] = rewrite(terse(clean(component(name))))
        pending.concat(refs_in(document["$defs"][name]))
      end
      document
    end

    def refs_in(node)
      case node
      when Hash
        own = node["$ref"].to_s.start_with?("#/$defs/") ? [ node["$ref"].delete_prefix("#/$defs/") ] : []
        own + node.values.flat_map { |v| refs_in(v) }
      when Array then node.flat_map { |v| refs_in(v) }
      else []
      end
    end

    def rewrite(node)
      case node
      when Hash then node.to_h { |k, v| [ k, k == "$ref" ? v.sub("#/components/schemas/", "#/$defs/") : rewrite(v) ] }
      when Array then node.map { |v| rewrite(v) }
      else node
      end
    end

    # Resolves component references in place (for small parameter schemas).
    def inline(node)
      case node
      when Hash
        return inline(clean(component(node["$ref"].delete_prefix("#/components/schemas/")))).merge(node.except("$ref")) if node["$ref"]

        node.transform_values { |v| inline(v) }
      when Array then node.map { |v| inline(v) }
      else node
      end
    end

    # A component without its prose (titles and descriptions, which the
    # contract and the docs site carry), to keep tools/list small.
    def terse(node)
      case node
      when Hash
        node.each_with_object({}) do |(k, v), out|
          next if %w[title description].include?(k) && !v.is_a?(Hash)

          out[k] = k == "properties" ? v.transform_values { |p| terse(p) } : terse(v)
        end
      when Array then node.map { |v| terse(v) }
      else node
      end
    end

    def clean(node)
      case node
      when Hash then node.reject { |k, _| DROP.include?(k) || k.start_with?("x-") }.transform_values { |v| clean(v) }
      when Array then node.map { |v| clean(v) }
      else node
      end
    end
  end
end
