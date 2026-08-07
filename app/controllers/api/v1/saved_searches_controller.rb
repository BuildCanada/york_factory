module Api
  module V1
    class SavedSearchesController < ApplicationController
      before_action :doorkeeper_authorize!
      before_action :set_saved_search, only: %i[show update destroy test]

      def index
        render json: { data: current_user.saved_searches.order(created_at: :desc).map { |search| serialize(search) } }
      end

      def show
        render json: serialize(@saved_search)
      end

      def create
        attributes = saved_search_attributes
        attributes["delivery_configuration"] ||= { "channels" => [ "email" ] }
        saved_search = current_user.saved_searches.build(attributes)
        checkpoint = Searchable.checkpoint.to_i
        saved_search.cursor_sequence = saved_search.start_policy == "backfill" ? 0 : checkpoint
        saved_search.next_run_at ||= Time.current

        if saved_search.save
          # PostHog: track saved search creation
          PostHog.capture(
            distinct_id: current_user.posthog_distinct_id,
            event: "saved_search_created",
            properties: {
              realm: saved_search.realm,
              start_policy: saved_search.start_policy,
              delivery_mode: saved_search.delivery_mode,
              poll_interval_seconds: saved_search.poll_interval_seconds
            }
          )
          render json: serialize(saved_search), status: :created
        else
          render json: { errors: saved_search.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        old_digest = @saved_search.definition_digest
        @saved_search.assign_attributes(saved_search_attributes)
        @saved_search.valid?
        definition_changed = old_digest != @saved_search.definition_digest
        if definition_changed
          checkpoint = Searchable.checkpoint.to_i
          @saved_search.cursor_sequence = @saved_search.start_policy == "backfill" ? 0 : checkpoint
          @saved_search.definition_version += 1
        end
        @saved_search.next_run_at = Time.current if definition_changed

        if @saved_search.save
          # PostHog: track saved search update
          PostHog.capture(
            distinct_id: current_user.posthog_distinct_id,
            event: "saved_search_updated",
            properties: {
              saved_search_id: @saved_search.id,
              realm: @saved_search.realm,
              definition_changed: definition_changed,
              enabled: @saved_search.enabled
            }
          )
          render json: serialize(@saved_search)
        else
          render json: { errors: @saved_search.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        # PostHog: track saved search deletion before it's gone
        PostHog.capture(
          distinct_id: current_user.posthog_distinct_id,
          event: "saved_search_deleted",
          properties: {
            saved_search_id: @saved_search.id,
            realm: @saved_search.realm
          }
        )
        @saved_search.destroy!
        head :no_content
      end

      def test
        result = Search::QueryRunner.new.call(@saved_search.definition, realm: @saved_search.realm, limit: 25)
        render json: { data: result.rows, meta: { query_count: result.query_count } }
      rescue Search::QueryCompiler::InvalidDefinition, ArgumentError => error
        render json: { error: "invalid_search", details: error.message }, status: :unprocessable_entity
      end

      private

      def current_user
        @current_user ||= User.find(doorkeeper_token.resource_owner_id)
      end

      def set_saved_search
        @saved_search = current_user.saved_searches.find(params[:id])
      end

      def saved_search_attributes
        payload = params.require(:saved_search)
        permitted = payload.permit(
          :name, :realm, :enabled, :poll_interval_seconds, :start_policy,
          :notify_on_update, :delivery_mode, :timezone
        ).to_h
        permitted["definition"] = payload[:definition].to_unsafe_h if payload[:definition].respond_to?(:to_unsafe_h)
        if payload[:delivery_configuration].respond_to?(:permit)
          configuration = payload[:delivery_configuration].permit(:digest_interval_seconds).to_h
          permitted["delivery_configuration"] = configuration.merge("channels" => [ "email" ])
        end
        permitted
      end

      def serialize(saved_search)
        {
          id: saved_search.id,
          name: saved_search.name,
          realm: saved_search.realm,
          definition: saved_search.definition,
          enabled: saved_search.enabled,
          poll_interval_seconds: saved_search.poll_interval_seconds,
          next_run_at: saved_search.next_run_at,
          start_policy: saved_search.start_policy,
          notify_on_update: saved_search.notify_on_update,
          delivery_mode: saved_search.delivery_mode,
          delivery_configuration: saved_search.delivery_configuration,
          timezone: saved_search.timezone,
          created_at: saved_search.created_at,
          updated_at: saved_search.updated_at
        }.compact
      end
    end
  end
end
