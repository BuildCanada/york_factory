module PublicApi
  module V1
    # GET /v1/search: entities by identifier or name, each hit saying how it matched.
    class SearchController < BaseController
      include PublicApiEntityLookup

      operation :index, :searchEntities

      def index
        q = parameters["q"].to_s.strip
        raise Problem.new(:query_too_broad, "q must have at least 2 characters other than spaces and punctuation.") if FactFactory::SearchQuery.too_broad?(q)
        return unless refuse_person_class!

        query = FactFactory::SearchQuery.new(release:, persons: persons?)
        hits = query.page(q:, mode: parameters["mode"], entity_class: parameters["class"], jurisdiction: parameters["jurisdiction"],
          limit:, after:)
        page, next_cursor = paginate(hits) { |h| [ h.rank, h.score_key, h.entity_id ] }
        entities = query.entities(page)
        data = page.filter_map do |hit|
          entity = entities[hit.entity_id] or next
          { type: "entity", entity: EntitySerializer.ref(entity), match: { kind: hit.kind, score: hit.score, matched_on: hit.matched_on } }
        end
        render_data({ data:, meta: list_meta(next_cursor:), links: page_links(next_cursor) })
      end

      private

      def limit = parameters["limit"] || 20

      # Persons are searchable by name with read:persons only.
      def refuse_person_class!
        return true unless parameters["class"] == "person" && !persons?

        render_insufficient_scope("read:persons")
        false
      end
    end
  end
end
