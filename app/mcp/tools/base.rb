module Mcp
  module Tools
    # A Build Canada MCP tool (docs/public-interface-design.md §7.1). Every tool
    # is read-only and idempotent, closed-world, answers with structuredContent
    # that matches its outputSchema, plus a text summary that ends with its
    # citations and the same JSON for clients that read only text.
    #
    # Failures a caller can act on (not found, bad arguments the contract
    # refuses, a missing scope, rate limits, a query too broad) are tool
    # errors: `isError: true` with `structuredContent: { error: <problem> }`,
    # which every outputSchema allows. Protocol errors (an unknown tool,
    # malformed JSON-RPC) are left to the gem. A subclass implements
    #
    #   def self.perform(ctx, **arguments) -> { ...structured result... }
    #   def self.summary(result) -> String (without the citations)
    #
    # and may declare `required_scopes "usage:read"`.
    class Base < MCP::Tool
      # Raised by a tool to fail with a problem (a Hash of RFC 9457 members).
      class Failure < StandardError
        attr_reader :problem

        def initialize(problem)
          @problem = problem.transform_keys(&:to_s)
          super(@problem["detail"])
        end
      end

      ANNOTATIONS = { read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false }.freeze

      CAVEATS_DOCS = PublicApi::Catalog::CAVEAT_DOCS

      class << self
        def inherited(subclass)
          super
          subclass.annotations(ANNOTATIONS.dup)
        end

        def required_scopes(*scopes)
          @required_scopes = scopes.map(&:to_s) if scopes.any?
          @required_scopes || [ "read:public" ]
        end

        def call(server_context:, **arguments)
          ctx = server_context[:mcp]
          missing = required_scopes.reject { |scope| ctx.scope?(scope) }
          fail_with!(insufficient_scope(missing)) if missing.any?

          # As a client will see it: JSON types, string keys.
          result = JSON.parse(JSON.generate(perform(ctx, **arguments)))
          ctx.meter.minimum!
          respond(result)
        rescue Failure => e
          ctx&.meter&.minimum!
          error_response(e.problem)
        rescue Meter::Refused => e
          error_response(e.problem.body(instance: ctx.request_id))
        end

        def fail_with!(problem) = raise(Failure, problem)

        # The response of a /v1 call, or a Failure with its problem.
        def expect_ok!(response)
          return response if response.ok?

          fail_with!(response.body.is_a?(Hash) ? response.body : { code: "internal_error", title: "Internal error", status: response.status,
                                                                   detail: "The data API answered #{response.status}." })
        end

        def insufficient_scope(scopes)
          scope = scopes.join(" ")
          { code: "insufficient_scope", title: "Insufficient scope", status: 403, required_scope: scope,
            type: "https://data.buildcanada.com/api/problems/insufficient-scope",
            detail: "This tool needs #{scope}. Reconnect and approve #{scope}, or use an API key that has it " \
                    "(https://auth.buildcanada.com/developers)." }
        end

        # --- responses ---

        def respond(result)
          citations = Array(result["citations"])
          text = [ summary(result), citation_text(citations) ].compact_blank.join("\n\n")
          MCP::Tool::Response.new(
            [ { type: "text", text: }, { type: "text", text: JSON.generate(result) } ],
            structured_content: result
          )
        end

        def error_response(problem)
          problem = problem.transform_keys(&:to_s).slice(*%w[type title status detail code required_scope retry_after_seconds docs]).compact
          text = "Error #{problem['code']}: #{problem['detail']}"
          text += " Retry in #{problem['retry_after_seconds']} seconds." if problem["retry_after_seconds"]
          MCP::Tool::Response.new([ { type: "text", text: } ], structured_content: { error: problem }, error: true)
        end

        def citation_text(citations)
          return nil if citations.empty?

          "Cite:\n" + citations.map { |c| "- #{c}" }.join("\n")
        end

        # "code: text" lines for a response's caveats. Agents should act on them.
        def caveat_lines(caveats)
          Array(caveats).map { |c| "- #{c['code']}: #{c['text']}" }
        end

        # A citation for a computed answer: the operation and the release.
        def operation_citation(path, release)
          "Build Canada data release #{release}, https://data.buildcanada.com#{path}"
        end

        def release_of(body) = body.dig("meta", "release")
      end
    end
  end
end
