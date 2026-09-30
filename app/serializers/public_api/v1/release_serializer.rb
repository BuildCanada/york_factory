module PublicApi
  module V1
    # Release, and the ExportFile objects of GET /v1/exports and datasets.
    module ReleaseSerializer
      module_function

      # `full` adds the pinned inputs, checks and changelog; list pages leave
      # them empty (Release.inputs).
      def release(r, full:)
        {
          id: Format.gid("Release", r.release_id),
          number: r.release_id,
          published_at: Format.timestamp(r.published_at),
          build_versions: { registry_build: r.build_version, code_revision: r.code_revision }.compact.transform_values(&:to_s),
          inputs: full ? inputs(r) : [],
          counts: FactFactory::ReleaseQuery.counts(r.release_id),
          checks: full ? checks(r) : [],
          changes: full ? changes(r) : [],
          links: { self: "/v1/releases/#{r.release_id}", exports: "/v1/exports?release=#{r.release_id}" }
        }
      end

      # Roster captures (api.releases.roster_captures: {roster key => [{id,
      # url, sha256, rows}]}) and spending snapshots ({label => {snapshot_id,
      # rows, ...}}).
      def inputs(r)
        captures = (r.roster_captures || {}).flat_map do |roster, list|
          Array(list).filter_map do |capture|
            next unless capture.is_a?(Hash)

            { kind: "capture", asset: "sources/#{roster}", sha256: Format.sha256(capture["sha256"]), snapshot_id: nil, retrieved_at: nil }
          end
        end
        snapshots = (r.spending_snapshots || {}).sort.filter_map do |label, state|
          snapshot = state.is_a?(Hash) ? state["snapshot_id"].to_s : ""
          next unless snapshot.match?(/\A\d+\z/)

          { kind: "iceberg_snapshot", asset: label.split("@").first, sha256: nil, snapshot_id: snapshot, retrieved_at: nil }
        end
        captures + snapshots
      end

      def checks(r)
        checks = r.checks || {}
        (Array(checks["registry"]) + Array(checks["api"])).filter_map do |check|
          next unless check.is_a?(Hash) && check["name"]

          detail = check["detail"]
          { name: check["name"].to_s, blocking: check["blocking"] ? true : false, passed: check["passed"] ? true : false,
            detail: detail.nil? || detail.is_a?(String) ? detail : detail.to_json }
        end
      end

      # The data changelog, from what the build recorded: entity versions
      # added and retired, and the spending sources whose snapshot changed.
      def changes(r)
        counts = r.counts || {}
        entities = counts["entities"].is_a?(Hash) ? counts["entities"] : {}
        changes = []
        changes << { kind: "entities_added", summary: "#{entities['added'].to_i} entity versions added.", count: entities["added"].to_i } if entities["added"].to_i.positive?
        changes << { kind: "entities_retired", summary: "#{entities['closed'].to_i} entity versions retired.", count: entities["closed"].to_i } if entities["closed"].to_i.positive?
        (r.spending_snapshots || {}).sort.each do |label, state|
          next unless state.is_a?(Hash) && state["changed"] && state["snapshot_id"]

          changes << { kind: "source_refreshed", summary: "#{label} moved to Iceberg snapshot #{state['snapshot_id']}.", count: state["rows"]&.to_i }
        end
        changes
      end

      def export(e, query)
        # Release exports are registry tables written from the read model, not
        # from an Iceberg snapshot, so they name no Iceberg table.
        {
          release: e.release_id, table: query.export_table(e), format: "parquet", url: query.export_url(e), sha256: e.sha256,
          rows: e.rows.to_i, bytes: e.bytes.to_i, iceberg: nil
        }
      end
    end
  end
end
