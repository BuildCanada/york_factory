module PublicApi
  module V1
    # Revision and Snapshot (the contract's components/schemas).
    module RevisionSerializer
      module_function

      # `served` is FactFactory::RevisionQuery::Served; `build` the
      # derived_builds row at the revision, if any.
      def revision(r, served:, build:)
        {
          id: Format.gid("Revision", r.id),
          number: r.id,
          kind: r.kind.to_s,
          reason: r.reason,
          committed_at: Format.timestamp(r.committed_at),
          inputs: json_object(r.inputs),
          versions: json_object(r.versions).presence,
          served: served.latest.present? && r.id <= served.latest,
          snapshots: served.snapshots.select { |_, number| number == r.id }.keys.sort,
          derived: build && {
            built_at: Format.timestamp(build.built_at),
            counts: json_object(build.counts),
            checks: Array(build.checks).select { |c| c.is_a?(Hash) }
          },
          links: { self: "/v1/revisions/#{r.id}" }
        }
      end

      def snapshot(s)
        {
          name: s.name, revision: s.revision_id, reason: s.reason, held_by: s.held_by, created_at: Format.timestamp(s.created_at),
          links: { self: "/v1/snapshots/#{s.name}", revision: "/v1/revisions/#{s.revision_id}" }
        }
      end

      def json_object(value)
        value = JSON.parse(value) if value.is_a?(String)
        value.is_a?(Hash) ? value : {}
      rescue JSON::ParserError
        {}
      end
    end
  end
end
