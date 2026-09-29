module Mcp
  # The Build Canada MCP server (docs/public-interface-design.md §7.1), built
  # per request on the official `mcp` gem: MCP 2026-07-28 (the stateless
  # lifecycle, server/discover) and the earlier `initialize` handshake
  # (2025-11-25 and before) for clients that still use it.
  module Server
    NAME = "buildcanada".freeze
    TOOLS = [ Tools::SearchEntities, Tools::GetEntity, Tools::EntitySpending, Tools::SearchSpending, Tools::DescribeData ].freeze

    INSTRUCTIONS = <<~TEXT.squish.freeze
      Build Canada's public data: the registry of Canadian governments, public bodies and organizations, and the
      federal money they receive and pay (grants, contributions, contracts, transfer payments, research awards,
      international projects), with provenance and a citation for every fact. Start with search_entities to turn
      a name into an ID. Amounts from different sources overlap; never add them. Call describe_data("spending
      semantics") before totalling. Pin the release from your first result as as_of on later calls, state it, and
      end answers with the citations the tools return. Read-only; no street addresses.
    TEXT

    CAPABILITIES = { tools: {}, resources: {}, prompts: {} }.freeze

    module_function

    def build(context)
      server = MCP::Server.new(
        name: NAME,
        title: "Build Canada data",
        version:,
        website_url: "https://data.buildcanada.com/api/mcp",
        instructions: INSTRUCTIONS,
        tools: TOOLS,
        prompts: Prompts.all,
        resources: Resources.resources,
        resource_templates: Resources.templates,
        server_context: { mcp: context },
        # Stateless: no session to send list-changed notifications or logs on.
        capabilities: CAPABILITIES,
        configuration: configuration
      )
      server.resources_read_handler { |params| Resources.read(params, context) }
      server
    end

    def version = @version ||= Rails.root.join("VERSION").then { |p| p.exist? ? p.read.strip : "0.1.0" }

    def configuration
      MCP::Configuration.new(
        # Results are checked against their outputSchema outside production;
        # in production a mismatch would fail the call, so it is left to tests.
        validate_tool_call_results: !Rails.env.production?,
        exception_reporter: ->(error, context) { Rails.error.report(error, handled: true, context: { mcp: context.to_s.first(500) }) }
      )
    end
  end
end
