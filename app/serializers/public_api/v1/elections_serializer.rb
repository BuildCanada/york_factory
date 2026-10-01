module PublicApi
  module V1
    # Election, Contest, District, Candidacy, CandidateContact, ResultReport and
    # ElectionResult (the contract's components/schemas). Values are served as
    # the administrator publishes them, addresses included.
    module ElectionsSerializer
      module_function

      def path_id(id) = ERB::Util.url_encode(id)

      def election(e, captures:)
        base = "/v1/elections/#{path_id(e.id)}"
        {
          id: e.id, jurisdiction: e.jurisdiction, administrator: e.administrator, kind: e.kind, called_on: e.called_on,
          voting_day: e.voting_day, return_day: e.return_day, nominations_close_at: e.nominations_close_at,
          registration_deadline_at: e.registration_deadline_at, mail_request_deadline_at: e.mail_request_deadline_at,
          mail_return_deadline_at: e.mail_return_deadline_at, advance_voting_starts_at: e.advance_voting_starts_at,
          advance_voting_ends_at: e.advance_voting_ends_at, polls_open_at: e.polls_open_at, polls_close_at: e.polls_close_at,
          voting_notes: e.voting_notes, where_to_vote_url: e.where_to_vote_url, source_url: e.source_url,
          capture: capture(captures[e.capture_sha256], fallback_url: e.source_url),
          links: { self: base, contests: "#{base}/contests", result_reports: "#{base}/result-reports" }
        }
      end

      def contest(c, office:, district:)
        base = "/v1/contests/#{path_id(c.id)}"
        {
          id: c.id, election_id: c.election_id,
          office: office && {
            id: office.id, title: office.title, title_fr: office.title_fr, body_name: office.body_name,
            body_level: office.body_level, jurisdiction: office.jurisdiction
          },
          district: district_ref(district, c.district_id),
          seats: c.seats.to_i, method: c.method, status: c.status, voting_day: c.voting_day,
          question_number: c.question_number, question_text: c.question_text, question_text_fr: c.question_text_fr,
          threshold_as_shown: c.threshold_as_shown,
          links: { self: base, candidacies: "#{base}/candidacies", results: "#{base}/results", district: "/v1/districts/#{path_id(c.district_id)}" }
        }
      end

      def district_ref(d, id)
        return { id:, boundary_set_id: id.to_s.split("/")[0..-2].join("/"), code: id.to_s.split("/").last.to_s.upcase, name_as_shown: id.to_s } unless d

        { id: d.id, boundary_set_id: d.boundary_set_id, code: d.code, name_as_shown: d.name_as_shown }
      end

      # `geometry` is whether the boundary was asked for (always on a get).
      def district(d, boundary_set:, geometry:)
        data = {
          id: d.id,
          boundary_set: {
            id: d.boundary_set_id, jurisdiction: boundary_set&.jurisdiction.to_s, kind: boundary_set&.kind.to_s,
            legal_instrument: boundary_set&.legal_instrument, in_force_from: boundary_set&.in_force_from, in_force_to: boundary_set&.in_force_to
          },
          code: d.code, name_as_shown: d.name_as_shown
        }
        data[:geometry] = geometry ? geojson(d["geometry_json"]) : nil
        data[:links] = { self: "/v1/districts/#{path_id(d.id)}" }
        data
      end

      def geojson(text)
        text.present? ? JSON.parse(text) : nil
      rescue JSON::ParserError
        nil
      end

      def candidacy(c, contacts:, captures:)
        {
          id: c.id, contest_id: c.contest_id, ballot_name: c.ballot_name, legal_name: c.legal_name, party_key: c.party_key,
          party_as_shown: c.party_as_shown, status: c.status, incumbent: c.incumbent,
          residence_address: c.residence_address, residence_city: c.residence_city, residence_province: c.residence_province,
          residence_postal_code: c.residence_postal_code,
          agents: Array(c.agents).select { |a| a.is_a?(Hash) },
          declared_result: c.declared_result, person_id: c.person_id, status_changed_at: Format.timestamp(c.status_changed_at),
          contacts: contacts.map { |contact| contact(contact) },
          capture: capture(captures[c.last_seen_capture]),
          links: { self: "/v1/candidacies/#{c.id}", contest: "/v1/contests/#{path_id(c.contest_id)}" }
        }
      end

      def contact(c)
        {
          kind: c.kind, platform: c.platform.presence, value: c.value, source_url: c.source_url, linked_from_url: c.linked_from_url,
          evidence_quote: c.evidence_quote, capture_sha256: Format.sha256(c.capture_sha256), checked_at: Format.timestamp(c.checked_at)
        }
      end

      def result_report(r, captures:)
        {
          id: r.id, election_id: r.election_id, stage: r.stage, polls_reported: r.polls_reported, polls_total: r.polls_total,
          published_at: r.published_at, published_at_as_shown: r.published_at_as_shown, retrieved_at: Format.timestamp(r.retrieved_at),
          source_url: r.source_url,
          capture: capture(captures[r.capture_sha256], sha: r.capture_sha256, fallback_url: r.source_url, retrieved_at: r.retrieved_at)
        }
      end

      def result(r)
        {
          report_id: r.report_id, contest_id: r.contest_id, candidacy_id: r.candidacy_id, answer: r.answer, measure: r.measure,
          measure_as_shown: r.measure_as_shown, polling_area_id: r.polling_area_id, unit_label_as_shown: r.unit_label_as_shown,
          ballot_type: r.ballot_type, ballot_type_as_shown: r.ballot_type_as_shown, round: r.round.to_i, value: r.value,
          reported_under: r.reported_under
        }
      end

      # An ElectionsCapture from an elections_captures row, or from what the
      # citing row knows when the capture row is missing.
      def capture(row, sha: nil, fallback_url: nil, retrieved_at: nil)
        sha = Format.sha256(row&.sha256 || sha) or return nil

        {
          sha256: sha, url: Format.capture_url(sha), source_url: row&.url || fallback_url,
          retrieved_at: Format.timestamp(row&.last_retrieved_at || retrieved_at)
        }
      end
    end
  end
end
