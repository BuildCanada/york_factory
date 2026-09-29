module Mcp
  # The MCP resources (docs/public-interface-design.md §7.1): the latest
  # release, spending sources and datasets, entities, dictionary terms and
  # the agent guides, each read in process from the /v1 operation it names
  # (so a resource costs that operation's units) or from app/mcp/guides.
  #
  #   buildcanada://releases/latest        GET /v1/releases/latest
  #   buildcanada://releases/{n}           GET /v1/releases/{n}
  #   buildcanada://spending/sources       GET /v1/spending/sources
  #   buildcanada://datasets               GET /v1/datasets
  #   buildcanada://datasets/{asset_key}   GET /v1/datasets/{asset_key} (the key percent-encoded: sources%2Fca%2Ftbs%2Fproactive_grants)
  #   buildcanada://entities/{id}          GET /v1/entities/{id}
  #   buildcanada://dictionary/{term}      GET /v1/dictionary/{term}
  #   buildcanada://guides/{slug}          agent-rules, citing
  module Resources
    SCHEME = "buildcanada://".freeze
    JSON_TYPE = "application/json".freeze
    GUIDES = Rails.root.join("app/mcp/guides")
    # A /v1 problem read as a resource: JSON-RPC server error, the problem in data.
    PROBLEM_CODE = -32000

    ROUTES = [
      [ %r{\Areleases/latest\z}, ->(_) { [ "/v1/releases/latest", "getLatestRelease" ] } ],
      [ %r{\Areleases/(?<n>\d+)\z}, ->(m) { [ "/v1/releases/#{m[:n]}", "getRelease" ] } ],
      [ %r{\Aspending/sources\z}, ->(_) { [ "/v1/spending/sources", "listSpendingSources", { limit: 200 } ] } ],
      [ %r{\Adatasets\z}, ->(_) { [ "/v1/datasets", "listDatasets", { limit: 200 } ] } ],
      [ %r{\Adatasets/(?<key>[^/]+)\z}, ->(m) { [ "/v1/datasets/#{ERB::Util.url_encode(CGI.unescape(m[:key]))}", "getDataset" ] } ],
      [ %r{\Aentities/(?<id>[0-9A-HJKMNP-TV-Z]{26})\z}, ->(m) { [ "/v1/entities/#{m[:id]}", "getEntity" ] } ],
      [ %r{\Adictionary/(?<term>[a-z][a-z0-9_]*)\z}, ->(m) { [ "/v1/dictionary/#{m[:term]}", "getDictionaryTerm" ] } ]
    ].freeze

    module_function

    def guides = GUIDES.glob("*.md").map { |p| p.basename(".md").to_s }.sort

    def resources
      [
        MCP::Resource.new(uri: "#{SCHEME}releases/latest", name: "latest-release", title: "Latest data release", mime_type: JSON_TYPE,
          description: "The latest Build Canada data release: its number (pass it as as_of), pinned inputs, row counts, checks and what changed."),
        MCP::Resource.new(uri: "#{SCHEME}spending/sources", name: "spending-sources", title: "Spending sources", mime_type: JSON_TYPE,
          description: "Every spending source: what a row records, what its amount measures, revisions, licence and caveats. Read before totalling."),
        MCP::Resource.new(uri: "#{SCHEME}datasets", name: "datasets", title: "Datasets", mime_type: JSON_TYPE,
          description: "Every dataset: publisher, licence, coverage (rows, fiscal years, known gaps), dictionary terms and bulk files.")
      ] + guides.map do |slug|
        MCP::Resource.new(uri: "#{SCHEME}guides/#{slug}", name: "guide-#{slug}", title: guide_title(slug), mime_type: "text/markdown",
          description: "A short guide for agents: #{guide_title(slug)}.")
      end
    end

    def templates
      [
        MCP::ResourceTemplate.new(uri_template: "#{SCHEME}entities/{id}", name: "entity", title: "Entity", mime_type: JSON_TYPE,
          description: "One registry entity by its 26-character ID, as GET /v1/entities/{id} returns it (latest release)."),
        MCP::ResourceTemplate.new(uri_template: "#{SCHEME}dictionary/{term}", name: "dictionary-term", title: "Dictionary term", mime_type: JSON_TYPE,
          description: "A data dictionary term (amount, fiscal_year, canonical_id, ...): meaning, type, units, values and per-dataset notes."),
        MCP::ResourceTemplate.new(uri_template: "#{SCHEME}datasets/{asset_key}", name: "dataset", title: "Dataset", mime_type: JSON_TYPE,
          description: "One dataset by asset key, percent-encoded (buildcanada://datasets/sources%2Fca%2Ftbs%2Fproactive_grants)."),
        MCP::ResourceTemplate.new(uri_template: "#{SCHEME}releases/{number}", name: "release", title: "Release", mime_type: JSON_TYPE,
          description: "One data release by number: pinned inputs, counts, checks and changes."),
        MCP::ResourceTemplate.new(uri_template: "#{SCHEME}guides/{slug}", name: "guide", title: "Guide", mime_type: "text/markdown",
          description: "A guide for agents: #{guides.join(', ')}.")
      ]
    end

    def guide_title(slug) = File.foreach(GUIDES.join("#{slug}.md")).first.to_s.delete_prefix("# ").strip

    # resources/read: [contents] for the URI, charged like the /v1 call.
    def read(params, ctx)
      uri = params[:uri].to_s
      rest = uri.delete_prefix(SCHEME)
      raise MCP::Server::ResourceNotFoundError.new(uri, params) if rest == uri

      if (slug = rest[%r{\Aguides/([a-z0-9-]+)\z}, 1]) && guides.include?(slug)
        ctx.meter.minimum!
        return [ { uri:, mimeType: "text/markdown", text: GUIDES.join("#{slug}.md").read } ]
      end

      pattern, target = ROUTES.find { |p, _| p.match?(rest) }
      raise MCP::Server::ResourceNotFoundError.new(uri, params) unless pattern

      path, operation, query = target.call(pattern.match(rest))
      response = ctx.api.get(path, operation:, **(query || {}))
      raise MCP::Server::ResourceNotFoundError.new(uri, params) if response.status == 404
      raise problem_error(response.body, params) unless response.ok?

      [ { uri:, mimeType: JSON_TYPE, text: JSON.generate(response.body) } ]
    rescue Meter::Refused => e
      raise problem_error(e.problem.body(instance: ctx.request_id), params)
    end

    def problem_error(problem, params)
      problem = problem.is_a?(Hash) ? problem : { "code" => "internal_error", "detail" => "The data API failed." }
      MCP::Server::RequestHandlerError.new("#{problem['code'] || problem[:code]}: #{problem['detail'] || problem[:detail]}", params,
        error_type: :resource_problem, error_code: PROBLEM_CODE, error_data: { problem: })
    end
  end
end
