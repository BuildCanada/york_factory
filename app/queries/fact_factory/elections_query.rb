module FactFactory
  # The elections tables (fact-factory docs/elections-model.md): elections,
  # contests, districts with their PostGIS boundaries, candidacies with their
  # contacts, result reports and results. Current state, not versioned by
  # registry revision: seeded tables are replaced on reload, candidacies and
  # contacts are upserted, results and reports are append-only.
  #
  # Of the candidate contacts, only those whose status is `verified` are served.
  # That is a correctness rule: a proposed or rejected contact is unconfirmed
  # (the value wasn't found on the page it claims, or nobody has checked).
  class ElectionsQuery
    VERIFIED = "verified".freeze

    def t(name) = FactFactoryRecord.table("elections_#{name}")

    def elections(jurisdiction: nil, kind: nil, limit:, after: nil)
      scope = Election.order(voting_day: :desc, id: :asc).limit(limit + 1)
      scope = scope.where(jurisdiction:) if jurisdiction
      scope = scope.where(kind:) if kind
      scope = scope.where("voting_day < :d OR (voting_day = :d AND id > :id)", d: after[0], id: after[1]) if after
      scope.to_a
    end

    def election(id) = Election.find_by(id:)

    def contests(election_id, district: nil, office: nil, limit:, after: nil)
      scope = Contest.where(election_id:).order(:id).limit(limit + 1)
      scope = scope.where(district_id: district) if district
      scope = scope.where(office_id: office) if office
      scope = scope.where("id > ?", after[0]) if after
      scope.to_a
    end

    def contest(id) = Contest.find_by(id:)

    def offices(ids) = Office.where(id: ids.compact.uniq).index_by(&:id)

    # {id => District}, without geometry.
    def district_refs(ids) = District.where(id: ids.compact.uniq).select(:id, :boundary_set_id, :code, :name_as_shown).index_by(&:id)

    def districts(boundary_set: nil, jurisdiction: nil, geometry: false, limit:, after: nil)
      scope = district_scope(geometry).order(:id).limit(limit + 1)
      scope = scope.where(boundary_set_id: boundary_set) if boundary_set
      scope = scope.where(boundary_set_id: BoundarySet.where(jurisdiction:).select(:id)) if jurisdiction
      scope = scope.where("#{t('districts')}.id > ?", after[0]) if after
      scope.to_a
    end

    def district(id) = district_scope(true).find_by(id:)

    def boundary_sets(ids) = BoundarySet.where(id: ids.compact.uniq).index_by(&:id)

    def candidacies(contest_id, limit:, after: nil)
      scope = Candidacy.where(contest_id:).order(:ballot_name, :id).limit(limit + 1)
      scope = scope.where("ballot_name > :name OR (ballot_name = :name AND id > :id)", name: after[0], id: after[1]) if after
      scope.to_a
    end

    def candidacy(id) = Candidacy.find_by(id:)

    # {candidacy_id => [CandidateContact]}: verified contacts only.
    def contacts(candidacy_ids)
      CandidateContact.where(candidacy_id: candidacy_ids, status: VERIFIED).order(:kind, :platform, :value).to_a.group_by(&:candidacy_id)
    end

    def result_reports(election_id, limit:, after: nil)
      scope = ResultReport.where(election_id:).order(:retrieved_at, :id).limit(limit + 1)
      scope = scope.where("retrieved_at > :at OR (retrieved_at = :at AND id > :id)", at: after[0].to_f, id: after[1]) if after
      scope.to_a
    end

    # The report a contest's results are read from: `report` when given (it
    # must be of the contest's election), else the election's latest.
    def report_for(contest, report: nil)
      scope = ResultReport.where(election_id: contest.election_id)
      report ? scope.find_by(id: report) : scope.order(retrieved_at: :desc, id: :desc).first
    end

    def results(contest_id, report_id:, measure: nil, polling_area: nil, limit:, after: nil)
      scope = ElectionResult.where(contest_id:, report_id:).order(:id).limit(limit + 1)
      scope = scope.where(measure:) if measure
      scope = scope.where(polling_area_id: polling_area) if polling_area
      scope = scope.where("id > ?", after[0]) if after
      scope.to_a
    end

    # {sha256 => ElectionsCapture}.
    def captures(digests) = ElectionsCapture.where(sha256: digests.compact.uniq).index_by(&:sha256)

    private

    # Districts, with the boundary as GeoJSON text when asked (PostGIS's
    # ST_AsGeoJSON, on the reader's search_path).
    def district_scope(geometry)
      columns = %w[id boundary_set_id code name_as_shown].map { |c| "#{t('districts')}.#{c}" }
      columns << "ST_AsGeoJSON(#{t('districts')}.geometry) AS geometry_json" if geometry
      District.select(columns.join(", "))
    end
  end
end
