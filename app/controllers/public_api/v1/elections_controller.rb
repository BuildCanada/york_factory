module PublicApi
  module V1
    # The elections operations: /v1/elections (and its contests and result
    # reports), /v1/contests/{id} (and its candidacies and results),
    # /v1/candidacies/{id} and /v1/districts. Elections data is current state,
    # not versioned by registry revision: these operations take no as_of, their
    # meta names the time they read it, and they are cached briefly.
    class ElectionsController < BaseController
      operation :index, :listElections
      operation :show, :getElection
      operation :contests, :listElectionContests
      operation :result_reports, :listElectionResultReports
      operation :contest, :getContest
      operation :candidacies, :listContestCandidacies
      operation :results, :listContestResults
      operation :candidacy, :getCandidacy
      operation :districts, :listDistricts
      operation :district, :getDistrict

      def index
        rows = query.elections(jurisdiction: parameters["jurisdiction"], kind: parameters["kind"], limit:, after:)
        page, next_cursor = paginate(rows, cursor_revision: nil) { |e| [ e.voting_day, e.id ] }
        captures = query.captures(page.map(&:capture_sha256))
        render_list(page.map { |e| ElectionsSerializer.election(e, captures:) }, next_cursor)
      end

      def show
        election = find_election
        render_one(ElectionsSerializer.election(election, captures: query.captures([ election.capture_sha256 ])))
      end

      def contests
        election = find_election
        rows = query.contests(election.id, district: parameters["district"], office: parameters["office"], limit:, after:)
        page, next_cursor = paginate(rows, cursor_revision: nil) { |c| [ c.id ] }
        render_list(serialize_contests(page), next_cursor)
      end

      def result_reports
        election = find_election
        rows = query.result_reports(election.id, limit:, after:)
        page, next_cursor = paginate(rows, cursor_revision: nil) { |r| [ r.retrieved_at, r.id ] }
        captures = query.captures(page.map(&:capture_sha256))
        render_list(page.map { |r| ElectionsSerializer.result_report(r, captures:) }, next_cursor)
      end

      def contest
        render_one(serialize_contests([ find_contest ]).first)
      end

      def candidacies
        contest = find_contest
        rows = query.candidacies(contest.id, limit:, after:)
        page, next_cursor = paginate(rows, cursor_revision: nil) { |c| [ c.ballot_name, c.id ] }
        render_list(serialize_candidacies(page), next_cursor)
      end

      def results
        contest = find_contest
        report = query.report_for(contest, report: parameters["report"])
        if parameters["report"] && report.nil?
          raise Problem.not_found("No result report #{parameters['report']} for election #{contest.election_id}.")
        end

        rows = report ? query.results(contest.id, report_id: report.id, measure: parameters["measure"], polling_area: parameters["polling_area"], limit:, after:) : []
        page, next_cursor = paginate(rows, cursor_revision: nil) { |r| [ r.id ] }
        render_list(page.map { |r| ElectionsSerializer.result(r) }, next_cursor)
      end

      def candidacy
        candidacy = query.candidacy(parameters["candidacy_id"]) or raise Problem.not_found("No candidacy #{parameters['candidacy_id']}.")
        render_one(serialize_candidacies([ candidacy ]).first)
      end

      def districts
        geometry = Array(parameters["expand"]).include?("geometry")
        rows = query.districts(boundary_set: parameters["boundary_set"], jurisdiction: parameters["jurisdiction"], geometry:, limit:, after:)
        page, next_cursor = paginate(rows, cursor_revision: nil) { |d| [ d.id ] }
        sets = query.boundary_sets(page.map(&:boundary_set_id))
        render_list(page.map { |d| ElectionsSerializer.district(d, boundary_set: sets[d.boundary_set_id], geometry:) }, next_cursor)
      end

      def district
        district = query.district(parameters["district_id"]) or raise Problem.not_found("No district #{parameters['district_id']}.")
        sets = query.boundary_sets([ district.boundary_set_id ])
        render_one(ElectionsSerializer.district(district, boundary_set: sets[district.boundary_set_id], geometry: true))
      end

      private

      def query = @query ||= FactFactory::ElectionsQuery.new

      def find_election
        query.election(parameters["election_id"]) or raise Problem.not_found("No election #{parameters['election_id']}.")
      end

      def find_contest
        query.contest(parameters["contest_id"]) or raise Problem.not_found("No contest #{parameters['contest_id']}.")
      end

      def serialize_contests(contests)
        offices = query.offices(contests.map(&:office_id))
        districts = query.district_refs(contests.map(&:district_id))
        contests.map { |c| ElectionsSerializer.contest(c, office: offices[c.office_id], district: districts[c.district_id]) }
      end

      def serialize_candidacies(candidacies)
        contacts = query.contacts(candidacies.map(&:id))
        captures = query.captures(candidacies.map(&:last_seen_capture))
        candidacies.map { |c| ElectionsSerializer.candidacy(c, contacts: contacts.fetch(c.id, []), captures:) }
      end

      def render_list(data, next_cursor)
        render_data({ data:, meta: current_meta.merge(limit:, next_cursor:, count: nil), links: page_links(next_cursor, pin: false) },
          revision: nil, pinned: false)
      end

      def render_one(data)
        render_data({ data:, meta: current_meta, links: { self: self_link(pin: false) } }, revision: nil, pinned: false)
      end
    end
  end
end
