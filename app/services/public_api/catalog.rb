module PublicApi
  # What the API says about its data, beyond the rows: the shared data
  # dictionary, each dataset's and spending source's metadata, and caveat
  # text. It is read from config/public_api/:
  #
  # - dictionary.json: fact-factory's docs/data-dictionary.yaml in the
  #   format of `fact-factory dictionary export` (catalog/dictionary.json),
  #   vendored at the commit its `source.repository` names;
  # - datasets.yml: titles, publishers, licences and cadences;
  # - caveats.yml: caveat text in English and French.
  #
  # None of it is versioned by release yet: the read model has no dictionary
  # or dataset tables (a WS-B follow-up). Row counts, snapshots and bulk files
  # do come from the release.
  module Catalog
    ROOT = Rails.root.join("config/public_api")
    CAVEAT_DOCS = "https://data.buildcanada.com/docs/caveats".freeze
    DICTIONARY_DOCS = "https://data.buildcanada.com/docs/dictionary".freeze

    # What `amount` measures per source (fact-factory serve/read_model.MEASURES).
    MEASURES = {
      "proactive_contracts" => "contract_value",
      "aggregated_contracts" => "aggregated_contract_value",
      "proactive_grants" => "agreement_value",
      "transfer_payments" => "payments_or_expenditure",
      "nserc_awards" => "award_amount",
      "sshrc_awards" => "award_amount",
      "cihr_awards" => "award_amount",
      "global_affairs_projects" => "commitment"
    }.freeze

    Source = Data.define(:key, :asset, :title, :publisher, :record_types, :record_meaning, :caveats, :known_gaps, :license, :cadence) do
      def measure = MEASURES.fetch(key)

      def amount_note = Catalog.asset_note(asset, "amount") || "The source's single best monetary value; see the dataset page."

      def fiscal_year_note = Catalog.asset_note(asset, "fiscal_year") || Catalog.definition("fiscal_year")&.dig("meaning").to_s

      def revisions_note
        Catalog.asset_note(asset, "canonical_id") || "No revisions: canonical_id equals external_id, and each row is its own agreement."
      end
    end

    RegistryDataset = Data.define(:asset, :table, :title, :record_meaning, :records, :publisher, :license, :cadence)

    module_function

    def dictionary
      @dictionary ||= JSON.parse(File.read(ROOT.join("dictionary.json")))
    end

    def dictionary_sha256 = dictionary.dig("source", "sha256")

    def definitions = dictionary.fetch("definitions")

    def definition(term) = definitions[term.to_s]

    def asset_notes(asset) = dictionary.fetch("assets").fetch(asset, {})

    def asset_note(asset, term)
      note = asset_notes(asset)[term.to_s]
      note&.to_s
    end

    # {asset key => note} for every asset that notes a difference from `term`.
    def notes_for_term(term)
      dictionary.fetch("assets").each_with_object({}) do |(asset, notes), out|
        out[asset] = notes[term].to_s if notes.is_a?(Hash) && notes.key?(term)
      end
    end

    def datasets_config
      @datasets_config ||= YAML.safe_load_file(ROOT.join("datasets.yml"))
    end

    def sources
      @sources ||= datasets_config.fetch("spending").map do |key, s|
        defaults = datasets_config.fetch("spending_defaults")
        Source.new(
          key:, asset: s.fetch("asset"), title: s.fetch("title"), publisher: s.fetch("publisher"),
          record_types: s.fetch("record_types"), record_meaning: s.fetch("record_meaning"),
          caveats: s.fetch("caveats", []), known_gaps: s.fetch("known_gaps", []),
          license: s.fetch("license", defaults.fetch("license")), cadence: s.fetch("cadence", defaults.fetch("cadence"))
        )
      end.index_by(&:key)
    end

    def source(key) = sources[key.to_s]

    def source_for_asset(asset) = sources.values.find { |s| s.asset == asset }

    def registry_datasets
      @registry_datasets ||= datasets_config.fetch("registry").map do |asset, d|
        defaults = datasets_config.fetch("registry_defaults")
        RegistryDataset.new(
          asset:, table: d.fetch("table"), title: d.fetch("title"), record_meaning: d.fetch("record_meaning"),
          records: d["records"], publisher: d.fetch("publisher", defaults["publisher"]),
          license: d.fetch("license", defaults.fetch("license")), cadence: d.fetch("cadence", defaults.fetch("cadence"))
        )
      end.index_by(&:asset)
    end

    def caveat_texts
      @caveat_texts ||= YAML.safe_load_file(ROOT.join("caveats.yml"))
    end

    # One Caveat object. Unknown codes are a programming error.
    def caveat(code, locale: "en", **values)
      texts = caveat_texts.fetch(code.to_s)
      text = format(texts.fetch(locale.to_s) { texts.fetch("en") }, **values)
      { code: code.to_s, text:, docs: "#{CAVEAT_DOCS}##{code}" }
    end
  end
end
