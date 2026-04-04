module Api
  module V1
    class TeamMembersController < CmsBaseController
      before_action :authenticate_admin!, only: [ :create, :update, :destroy, :bulk_update ]
      before_action :set_team_member, only: [ :update, :destroy ]

      def index
        scope = preview_mode? ? TeamMember.all : TeamMember.published
        scope = scope.ordered
        scope = scope.by_role(params[:role]) if params[:role].present?

        render json: {
          data: scope.map { |tm| serialize_team_member(tm) }
        }
      end

      def create
        member = TeamMember.new(team_member_params)
        if member.save
          render json: serialize_team_member(member), status: :created
        else
          render json: { errors: member.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @team_member.update(team_member_params)
          render json: serialize_team_member(@team_member)
        else
          render json: { errors: @team_member.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def bulk_update
        ActiveRecord::Base.transaction do
          updates = params.require(:team_members)
          updates.each do |entry|
            member = TeamMember.find(entry[:id])
            member.update!(entry.permit(:position, :role, :name, :title_en, :title_fr))
          end
        end
        render json: { message: "Updated" }
      end

      def destroy
        @team_member.destroy!
        head :no_content
      end

      private

      def set_team_member
        @team_member = TeamMember.find(params[:id])
      end

      def team_member_params
        params.require(:team_member).permit(
          :name, :role, :twitter_url, :linkedin_url, :position, :profile_photo,
          :title_en, :title_fr
        )
      end

      def serialize_team_member(member)
        {
          id: member.id,
          name: member.name,
          slug: member.slug,
          title: member.title,
          role: member.role,
          twitter_url: member.twitter_url,
          linkedin_url: member.linkedin_url,
          position: member.position,
          profile_photo_url: image_url(member.profile_photo)
        }
      end
    end
  end
end
