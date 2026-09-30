module PublicApi
  module V1
    # GET /v1/exports: a release's bulk Parquet files (api.release_exports).
    class ExportsController < BaseController
      operation :index, :listExports

      def index
        number = parameters["release"]
        resolved = AsOf.resolve(number&.to_s, releases:)
        @as_of = resolved
        if decoded_cursor && decoded_cursor.release != resolved.release
          raise Problem.new(:release_mismatch, "This cursor belongs to release #{decoded_cursor.release}. Repeat with release=#{decoded_cursor.release}, or drop the cursor.",
            cursor_release: decoded_cursor.release)
        end
        query = FactFactory::DatasetQuery.new(release: resolved.release)
        files = query.exports(table: parameters["table"])
        files = files.select { |e| query.export_table(e) > after.first } if after
        page, next_cursor = paginate(files.first(limit + 1), cursor_release: resolved.release) { |e| [ query.export_table(e) ] }
        render_data({
          data: page.map { |e| ReleaseSerializer.export(e, query) },
          meta: list_meta(next_cursor:),
          links: page_links(next_cursor, pin: false)
        }, pinned: number.present?)
      end
    end
  end
end
