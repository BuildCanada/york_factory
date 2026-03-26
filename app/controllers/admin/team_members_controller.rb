module Admin
  class TeamMembersController < BaseController
    before_action :set_team_member, only: [:show, :edit, :update, :destroy, :retranslate]

    def index
      @team_members = TeamMember.ordered
    end

    def show; end
    def new; @team_member = TeamMember.new; end
    def edit; end

    def create
      @team_member = TeamMember.new(team_member_params)
      if @team_member.save
        redirect_to admin_team_member_path(@team_member), notice: "Team member created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      purge_attachment(:profile_photo)
      if @team_member.update(team_member_params)
        redirect_to admin_team_member_path(@team_member), notice: "Team member updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @team_member.destroy!
      redirect_to admin_team_members_path, notice: "Team member deleted."
    end

    def reorder
      params[:ordered_ids].each_with_index do |id, index|
        TeamMember.where(id: id).update_all(position: index)
      end
      head :ok
    end

    def retranslate
      @team_member.update(title_fr: nil)
      TranslateRecordJob.perform_later("TeamMember", @team_member.id)
      head :ok
    end

    private

    def set_team_member
      @team_member = TeamMember.friendly.find(params[:id])
    end

    def team_member_params
      params.require(:team_member).permit(
        :name, :role, :twitter_url, :linkedin_url, :position, :published_at, :profile_photo,
        :title_en, :title_fr
      )
    end

    def purge_attachment(name)
      @team_member.send(name).purge if params.dig(:team_member, "purge_#{name}") == "1"
    end
  end
end
