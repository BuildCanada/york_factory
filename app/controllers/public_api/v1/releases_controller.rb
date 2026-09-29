module PublicApi
  module V1
    # GET /v1/releases, /v1/releases/latest and /v1/releases/{release}.
    class ReleasesController < BaseController
      operation :index, :listReleases
      operation :latest, :getLatestRelease
      operation :show, :getRelease

      def index
        latest = AsOf.resolve(nil, releases:).release
        rows = FactFactory::ReleaseQuery.page(limit: limit + 1, before: after&.first)
        page, next_cursor = paginate(rows, cursor_release: nil) { |r| [ r.release_id ] }
        render_data({
          data: page.map { |r| ReleaseSerializer.release(r, full: false) },
          meta: list_meta(next_cursor:, release: latest),
          links: page_links(next_cursor, pin: false)
        }, release: latest, pinned: false)
      end

      def latest
        number = AsOf.resolve(nil, releases:).release
        render_release(FactFactory::ReleaseQuery.find(number), pinned: false)
      end

      def show
        number = parameters["release"]
        AsOf.resolve(number.to_s, releases:)
        render_release(FactFactory::ReleaseQuery.find(number), pinned: true)
      end

      private

      def render_release(row, pinned:)
        render_data({
          data: ReleaseSerializer.release(row, full: true),
          meta: meta(release: row.release_id),
          links: { self: "/v1/releases/#{row.release_id}" }
        }, release: row.release_id, pinned:)
      end
    end
  end
end
