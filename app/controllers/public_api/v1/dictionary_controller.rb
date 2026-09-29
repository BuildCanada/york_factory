module PublicApi
  module V1
    # GET /v1/dictionary and /v1/dictionary/{term}: fact-factory's shared data
    # dictionary (config/public_api/dictionary.json). The dictionary is not yet
    # versioned by release, so a pinned as_of says so in a caveat and is not
    # cached as immutable.
    class DictionaryController < BaseController
      operation :index, :listDictionaryTerms
      operation :show, :getDictionaryTerm

      TERM = /\A[a-z][a-z0-9_]*\z/

      def index
        q = parameters["q"]&.downcase
        terms = Catalog.definitions.select { |name, _| name.match?(TERM) }.sort_by(&:first)
        terms = terms.select { |name, d| name.include?(q) || d["meaning"].to_s.downcase.include?(q) } if q
        terms = terms.select { |name, _| name > after.first } if after
        page, next_cursor = paginate(terms.first(limit + 1)) { |(name, _)| [ name ] }
        render_data({
          data: page.map { |name, d| CatalogSerializer.term(name, d) },
          meta: list_meta(next_cursor:, caveats:),
          links: page_links(next_cursor)
        }, pinned: false)
      end

      def show
        name = parameters["term"]
        definition = Catalog.definition(name) or raise Problem.not_found("No dictionary term #{name}.")
        render_data({ data: CatalogSerializer.term(name, definition, notes: true), meta: meta(caveats:), links: { self: self_link } }, pinned: false)
      end

      private

      def caveats = parameters["as_of"] ? [ Catalog.caveat(:dictionary_not_pinned, locale:) ] : []
    end
  end
end
