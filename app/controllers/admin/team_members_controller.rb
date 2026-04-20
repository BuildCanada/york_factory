module Admin
  class TeamMembersController < BaseController
    before_action :set_team_member, only: [ :show, :edit, :update, :destroy, :retranslate ]

    def index
      @roles = TeamMember.distinct.where.not(role: nil).pluck(:role).sort
      @selected_role = params[:role].presence
      @min_memos = params[:min_memos].presence&.to_i

      scope = TeamMember.ordered
      scope = scope.by_role(@selected_role) if @selected_role

      @memo_counts = memo_counts_for(scope)
      @team_members = scope.to_a
      if @min_memos == 0
        @team_members = @team_members.select { |m| @memo_counts[m.id] == 0 }
      elsif @min_memos
        @team_members = @team_members.select { |m| @memo_counts[m.id] >= @min_memos }
      end
    end

    def show
      @authored_memos = Memo.where(author_id: @team_member.id).or(Memo.where(co_author_id: @team_member.id)).order(published_at: :desc, created_at: :desc)
    end
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
        if inline_role_update?
          redirect_back fallback_location: admin_team_members_path, notice: "Role updated."
        else
          redirect_to admin_team_member_path(@team_member), notice: "Team member updated."
        end
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
      TranslateRecordJob.perform_later(@team_member)
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

    def inline_role_update?
      submitted = (params[:team_member] || {}).keys - ["role"]
      submitted.empty?
    end

    def memo_counts_for(members)
      ids = members.map(&:id)
      authored = Memo.where(author_id: ids).group(:author_id).count
      co_authored = Memo.where(co_author_id: ids).group(:co_author_id).count
      Hash.new(0).tap do |h|
        ids.each { |id| h[id] = authored.fetch(id, 0) + co_authored.fetch(id, 0) }
      end
    end
  end
end
