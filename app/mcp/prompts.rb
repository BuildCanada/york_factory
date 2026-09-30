module Mcp
  # The MCP prompts (docs/public-interface-design.md §7.1): worked plans for
  # the two questions the server exists to answer, using the phase 1 tools.
  module Prompts
    module_function

    def all = [ investigate_recipient, follow_the_money ]

    def investigate_recipient
      MCP::Prompt.define(
        name: "investigate_recipient",
        title: "Investigate a recipient of federal money",
        description: "Find an organization and report the federal money it received, per source and year, with citations.",
        arguments: [ MCP::Prompt::Argument.new(name: "name", description: "The organization's name, ideally with its place, or a business number.", required: true) ]
      ) do |args, server_context: nil|
        Prompts.message(<<~TEXT)
          Investigate the federal money received by "#{Prompts.arg(args, :name)}", using the Build Canada tools.

          1. Call describe_data with topic "spending semantics" and follow its rules.
          2. Call search_entities with the name (add jurisdiction if you know it). Pick the identifier or exact match;
             if only fuzzy candidates come back, say so and ask which one is meant. Note the release in the result and
             pass it as as_of on every later call.
          3. Call get_entity with include ["identifiers", "lineage"] to confirm it is the right entity and to find
             predecessors (amalgamated or renamed entities).
          4. Call entity_spending with role "recipient" and group_by ["source", "fiscal_year"]. For each predecessor,
             call it again and report it separately.
          5. Report per source and fiscal year with each source's measure. Never add amounts across sources. Mention
             unlinked occurrences and every caveat that applies. End with the citations the tools returned.
        TEXT
      end
    end

    def follow_the_money
      MCP::Prompt.define(
        name: "follow_the_money",
        title: "Follow the money",
        description: "Trace who funds an organization, and whom a department or agency funds, with citations.",
        arguments: [ MCP::Prompt::Argument.new(name: "person_or_org", description: "An organization, department, agency or person.", required: true) ]
      ) do |args, server_context: nil|
        Prompts.message(<<~TEXT)
          Follow the federal money around "#{Prompts.arg(args, :person_or_org)}", using the Build Canada tools.

          1. Call describe_data with topic "spending semantics" and follow its rules.
          2. Call search_entities to find it; confirm with get_entity (include ["relationships", "lineage"]). Keep the
             release from the first result as as_of for every later call.
          3. If it is a department, agency or other payer, call entity_spending with role "payer" and group_by
             ["source", "counterparty"] to see whom it funds. Otherwise call it with role "recipient" and the same
             group_by to see who funds it.
          4. For the largest counterparties, call entity_spending on them, and search_spending with payer and
             recipient set, to show the individual agreements.
          5. A person entity is Build Canada's clustering of records, not a legal identity: say which records it
             groups. A role's observed_from is when a filing first showed it, not the appointment date.
          6. Report per source, never adding across sources, name each measure, and end with the citations.
        TEXT
      end
    end

    def arg(args, name) = args.to_h.transform_keys(&:to_sym)[name]

    def message(text) = MCP::Prompt::Result.new(messages: [ MCP::Prompt::Message.new(role: "user", content: MCP::Content::Text.new(text)) ])
  end
end
