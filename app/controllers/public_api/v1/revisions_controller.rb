module PublicApi
  module V1
    # GET /v1/revisions, /v1/revisions/latest, /v1/revisions/{revision},
    # /v1/snapshots and /v1/snapshots/{name}: the registry's committed revisions
    # and the snapshots that name them (read-only).
    class RevisionsController < BaseController
      operation :index, :listRevisions
      operation :latest, :getLatestRevision
      operation :show, :getRevision
      operation :snapshots, :listSnapshots
      operation :snapshot, :getSnapshot

      def index
        latest = AsOf.resolve(nil, served:).revision
        rows = FactFactory::RevisionQuery.page(limit:, before: after&.first)
        page, next_cursor = paginate(rows, cursor_revision: nil) { |r| [ r.id ] }
        builds = FactFactory::DerivedBuild.where(revision_id: page.map(&:id)).index_by(&:revision_id)
        render_data({
          data: page.map { |r| RevisionSerializer.revision(r, served:, build: builds[r.id]) },
          meta: list_meta(next_cursor:, revision: latest, snapshot: served.snapshot_for(latest)),
          links: page_links(next_cursor, pin: false)
        }, revision: latest, pinned: false)
      end

      def latest
        number = AsOf.resolve(nil, served:).revision
        render_revision(number, pinned: false)
      end

      def show
        number = parameters["revision"]
        row = FactFactory::RevisionQuery.find(number) or raise Problem.not_found("Revision #{number} was not committed.")
        render_revision(row.id, pinned: true, row:)
      end

      def snapshots
        latest = AsOf.resolve(nil, served:).revision
        rows = FactFactory::RevisionQuery.snapshots_page(limit:, after:)
        page, next_cursor = paginate(rows, cursor_revision: nil) { |s| [ s.created_at, s.name ] }
        render_data({
          data: page.map { |s| RevisionSerializer.snapshot(s) },
          meta: list_meta(next_cursor:, revision: latest, snapshot: served.snapshot_for(latest)),
          links: page_links(next_cursor, pin: false)
        }, revision: latest, pinned: false)
      end

      def snapshot
        name = parameters["name"]
        row = FactFactory::RevisionQuery.snapshot(name) or raise Problem.not_found("No snapshot named #{name}.")
        render_data({
          data: RevisionSerializer.snapshot(row),
          meta: meta(revision: row.revision_id, snapshot: row.name),
          links: { self: "/v1/snapshots/#{row.name}" }
        }, revision: row.revision_id, pinned: false)
      end

      private

      # Any committed revision is described, served or not (`served` says);
      # only served ones can be read with as_of.
      def render_revision(number, pinned:, row: FactFactory::RevisionQuery.find(number))
        render_data({
          data: RevisionSerializer.revision(row, served:, build: FactFactory::RevisionQuery.build(number)),
          meta: meta(revision: number, snapshot: served.snapshot_for(number)),
          links: { self: "/v1/revisions/#{number}" }
        }, revision: number, pinned:)
      end
    end
  end
end
