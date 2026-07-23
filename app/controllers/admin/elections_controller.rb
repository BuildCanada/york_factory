module Admin
  class ElectionsController < BaseController
    def index
      @elections = Warehouse::Election.includes(:jurisdiction).order(election_date: :desc)
    end

    def show
      @election = Warehouse::Election.includes(races: { candidates: { photo_attachment: :blob } }).find(params[:id])
      @races = @election.races.sort_by do |race|
        [ Warehouse::ElectionRace.office_types.keys.index(race.office_type),
          race.office_body.to_s, race.district_number.to_i ]
      end
    end

    # Queues photo-suggestion lookups (Wikipedia + campaign-site og:image)
    # for every active candidate still missing a photo. Suggestions land in
    # the review column on the election page — nothing is published.
    def fetch_photo_suggestions
      election = Warehouse::Election.find(params[:id])
      candidates = Warehouse::ElectionCandidate
        .where(election_race_id: election.races.select(:id), status: "active")
        .where.missing(:photo_attachment)

      candidates.find_each { |candidate| candidate.photo_suggester.suggest_later }

      redirect_to admin_election_path(election),
        notice: "Queued photo suggestions for #{candidates.count} candidates without photos."
    end
  end
end
