module Api
  module V1
    class ElectionsController < CmsBaseController
      def index
        elections = visible_elections.includes(:jurisdiction).order(election_date: :desc)
        render json: { data: elections.map { |e| serialize_election(e) } }
      end

      def show
        election = visible_elections
          .includes(:jurisdiction, races: :candidates)
          .find_by!(slug: params[:slug])
        render json: serialize_election(election, races: ::Warehouse::ElectionRace.sorted(election.races))
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      private

      # Drafts and scheduled elections are invisible until published — an
      # election is assembled in admin (races, then candidates) and a
      # half-entered one shouldn't reach the site. An admin token previews them.
      def visible_elections
        preview_mode? ? ::Warehouse::Election.all : ::Warehouse::Election.published
      end

      def serialize_election(election, races: nil)
        base = {
          slug: election.slug,
          name: election.name,
          kind: election.kind,
          election_date: election.election_date,
          nomination_close_date: election.nomination_close_date,
          jurisdiction: {
            name: election.jurisdiction.name,
            slug: election.jurisdiction.slug,
            level: election.jurisdiction.level
          },
          updated_at: election.updated_at
        }
        base[:races] = races.map { |r| serialize_race(r) } if races
        base
      end

      def serialize_race(race)
        {
          office_type: race.office_type,
          district_type: race.district_type,
          district_number: race.district_number,
          district_name: race.district_name,
          # Brampton's districts pair wards, so district_number (the lowest
          # ward) doesn't identify them on its own; nil where a district is a
          # single ward, as in Toronto.
          ward_numbers: race.metadata["ward_numbers"],
          office_body: race.office_body,
          candidates: visible_candidates(race).map { |c| serialize_candidate(c) }
        }
      end

      # Withdrawn candidates stay in the database — the City's withdrawn feed
      # is the only record that they ever ran, and the loaders keep flagging
      # them — but they're off the ballot, so the public API omits them.
      # Filtered in Ruby to keep the show action's :candidates preload.
      def visible_candidates(race)
        race.candidates.reject(&:withdrawn?)
          .sort_by { |c| [ c.last_name.to_s.downcase, c.first_name.to_s.downcase ] }
      end

      def serialize_candidate(candidate)
        {
          full_name: candidate.full_name,
          first_name: candidate.first_name,
          last_name: candidate.last_name,
          status: candidate.status,
          nomination_date: candidate.nomination_date,
          withdrawn_date: candidate.withdrawn_date,
          website: candidate.website,
          social_links: candidate.social_links,
          photo_url: image_url(candidate.photo),
          photo_attribution: candidate.photo_attribution
        }
      end
    end
  end
end
