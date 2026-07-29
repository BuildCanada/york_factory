module Admin
  # Races are normally created by the candidate-list loaders; this exists so a
  # region with no machine-readable source can be built by hand.
  class ElectionRacesController < BaseController
    before_action :set_election
    before_action :set_race, only: %i[edit update destroy]

    def new
      @race = @election.races.new(office_type: "councillor", district_type: "ward")
    end

    def edit; end

    def create
      @race = @election.races.new(race_params)
      if @race.save
        redirect_to admin_election_path(@election), notice: "#{@race.label} added."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @race.update(race_params)
        redirect_to admin_election_path(@election), notice: "#{@race.label} updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @race.destroy!
      redirect_to admin_election_path(@election), notice: "#{@race.label} and its candidates deleted."
    end

    private

    def set_election
      @election = Warehouse::Election.find(params[:election_id])
    end

    def set_race
      @race = @election.races.find(params[:id])
    end

    def race_params
      attributes = params.require(:warehouse_election_race)
        .permit(:office_type, :district_type, :district_number, :district_name, :office_body)

      # district_number and office_body are part of the race's identity, so a
      # blank field has to mean NULL rather than "" or 0.
      attributes[:district_number] = attributes[:district_number].presence
      attributes[:office_body] = attributes[:office_body].presence
      attributes[:district_name] = attributes[:district_name].presence
      attributes.merge(metadata: metadata)
    end

    # ward_numbers is what the public API exposes for districts that cover more
    # than one ward; at-large races carry none.
    def metadata
      existing = @race&.metadata || {}
      wards = params[:ward_numbers].to_s.scan(/\d+/).map(&:to_i).uniq.sort
      existing.merge("ward_numbers" => wards.presence)
    end
  end
end
