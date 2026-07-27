module Admin
  class ElectionsController < BaseController
    before_action :set_election, only: %i[show edit update destroy fetch_photo_suggestions]

    def index
      @elections = Warehouse::Election.includes(:jurisdiction).order(election_date: :desc)
    end

    def show
      @races = Warehouse::ElectionRace.sorted(@election.races)
    end

    def new
      @election = Warehouse::Election.new(kind: "municipal")
    end

    def edit; end

    def create
      @election = Warehouse::Election.new(election_params)
      assign_new_jurisdiction(@election)

      if @election.errors.empty? && @election.save
        redirect_to admin_election_path(@election), notice: "Election created. Add its races next."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @election.assign_attributes(election_params)
      assign_new_jurisdiction(@election)

      if @election.errors.empty? && @election.save
        redirect_to admin_election_path(@election), notice: "Election updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @election.destroy!
      redirect_to admin_elections_path, notice: "#{@election.name} deleted."
    end

    # Queues photo-suggestion lookups (Wikipedia + campaign-site og:image)
    # for every active candidate still missing a photo. Suggestions land in
    # the review column on the election page — nothing is published.
    def fetch_photo_suggestions
      candidates = Warehouse::ElectionCandidate
        .where(election_race_id: @election.races.select(:id), status: "active")
        .where.missing(:photo_attachment)

      candidates.find_each { |candidate| candidate.photo_suggester.suggest_later }

      redirect_to admin_election_path(@election),
        notice: "Queued photo suggestions for #{candidates.count} candidates without photos."
    end

    private

    def set_election
      @election = Warehouse::Election.includes(races: { candidates: { photo_attachment: :blob } }).find(params[:id])
    end

    def election_params
      params.require(:warehouse_election)
        .permit(:name, :slug, :kind, :jurisdiction_id, :election_date, :nomination_close_date)
    end

    # A new region needs a jurisdiction that may not exist yet, and creating
    # one is otherwise a console job. Filling in the "new jurisdiction" name on
    # the form takes precedence over the dropdown; its validation errors are
    # copied onto the election so the form can show them.
    def assign_new_jurisdiction(election)
      attributes = params[:new_jurisdiction]
      return if attributes.blank? || attributes[:name].blank?

      slug = attributes[:slug].presence || attributes[:name].parameterize
      jurisdiction = Warehouse::Jurisdiction.find_or_initialize_by(slug: slug)
      if jurisdiction.new_record?
        jurisdiction.assign_attributes(
          name: attributes[:name],
          code: attributes[:code].presence || slug.upcase,
          level: attributes[:level].presence || "municipal",
          fiscal_year_start_month: 1,
          default_currency: "CAD"
        )
      end

      if jurisdiction.save
        election.jurisdiction = jurisdiction
      else
        jurisdiction.errors.full_messages.each { |message| election.errors.add(:jurisdiction, message) }
      end
    end
  end
end
