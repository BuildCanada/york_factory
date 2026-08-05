require "json"
require "uri"

module Admin
  class SearchController < BaseController
    DEFAULT_FORM = {
      "realm" => "media",
      "mode" => "hybrid",
      "language" => "en",
      "lexical_match" => "all_tokens",
      "semantic_max_distance" => "0.5",
      "limit" => "25",
      "email" => "1",
      "start_policy" => "future_only",
      "poll_interval_seconds" => "60",
      "delivery_mode" => "instant",
      "digest_interval_seconds" => "3600"
    }.freeze
    DEFAULT_QUERY_RUNNER_FACTORY = -> { Search::QueryRunner.new }

    class_attribute :query_runner_factory, default: DEFAULT_QUERY_RUNNER_FACTORY

    def index
      @form = DEFAULT_FORM.dup
      load_page
    end

    def execute
      @form = DEFAULT_FORM.merge(search_params.to_h)
      definition = build_definition(@form)

      if params[:operation] == "save"
        save_search(definition)
      else
        run_query(definition)
        load_page
        render :index
      end
    rescue Search::QueryCompiler::InvalidDefinition, JSON::ParserError, ArgumentError => error
      render_error(error.message)
    rescue StandardError => error
      Rails.error.report(error)
      render_error("Search provider error: #{error.message.to_s.truncate(300)}")
    end

    def test_saved_search
      saved_search = current_user.saved_searches.find(params[:id])
      @form = form_for(saved_search)
      run_query(saved_search.definition, realm: saved_search.realm)
      @tested_saved_search = saved_search
      load_page
      render :index
    rescue ActiveRecord::RecordNotFound
      raise
    rescue Search::QueryCompiler::InvalidDefinition, ArgumentError => error
      @form ||= DEFAULT_FORM.dup
      render_error(error.message)
    rescue StandardError => error
      Rails.error.report(error)
      @form ||= DEFAULT_FORM.dup
      render_error("Search provider error: #{error.message.to_s.truncate(300)}")
    end

    def destroy_saved_search
      current_user.saved_searches.find(params[:id]).destroy!
      redirect_to admin_search_path, notice: "Saved search deleted."
    end

    private

    def search_params
      params.fetch(:search, {}).permit(
        :name, :realm, :mode, :text, :language, :lexical_match,
        :semantic_max_distance, :limit, :publisher_domain, :content_type,
        :published_after, :filters_json, :email, :webhook_url, :start_policy,
        :poll_interval_seconds, :delivery_mode, :digest_interval_seconds,
        :notify_on_update
      )
    end

    def build_definition(form)
      realm = form.fetch("realm", "media")
      mode = form.fetch("mode", "hybrid")
      definition = {
        "version" => 1,
        "realm" => realm,
        "mode" => mode,
        "language" => form.fetch("language", "en")
      }
      definition["text"] = form["text"].to_s.strip if mode != "filter_only"
      definition["lexical_match"] = form.fetch("lexical_match", "all_tokens") if %w[lexical hybrid].include?(mode)
      if %w[semantic hybrid].include?(mode)
        definition["semantic_max_distance"] = Float(form.fetch("semantic_max_distance", "0.5"))
      end

      filters = shortcut_filters(form)
      if form["filters_json"].present?
        advanced = JSON.parse(form["filters_json"])
        raise ArgumentError, "Advanced filters must be a JSON object" unless advanced.is_a?(Hash)

        filters << advanced
      end
      definition["filters"] = filters.one? ? filters.first : { "all" => filters } if filters.any?

      Search::QueryCompiler.new(definition, realm:)
      definition
    end

    def shortcut_filters(form)
      filters = []
      return filters unless form["realm"] == "media"

      if form["publisher_domain"].present?
        filters << { "field" => "publisher_domain", "op" => "eq", "value" => form["publisher_domain"] }
      end
      if form["content_type"].present?
        filters << { "field" => "content_type", "op" => "eq", "value" => form["content_type"] }
      end
      if form["published_after"].present?
        published_after = Time.zone.parse(form["published_after"])
        raise ArgumentError, "Published after is not a valid date and time" unless published_after

        filters << { "field" => "published_at", "op" => "gte", "value" => published_after.iso8601(6) }
      end
      filters
    end

    def run_query(definition, realm: definition["realm"])
      limit = @form.fetch("limit", 25).to_i.clamp(1, 100)
      @result = self.class.query_runner_factory.call.call(definition, realm:, limit:)
      @executed_definition = definition
    end

    def save_search(definition)
      channels = []
      channels << "email" if ActiveModel::Type::Boolean.new.cast(@form["email"])
      channels << "webhook" if @form["webhook_url"].present?
      raise ArgumentError, "Choose email or enter a webhook URL" if channels.empty?

      validate_webhook_url!(@form["webhook_url"]) if channels.include?("webhook")
      delivery_configuration = { "channels" => channels }
      delivery_configuration["webhook_url"] = @form["webhook_url"] if channels.include?("webhook")
      if @form["delivery_mode"] == "digest"
        delivery_configuration["digest_interval_seconds"] = Integer(@form["digest_interval_seconds"])
      end

      checkpoint = Searchable.checkpoint.to_i
      saved_search = current_user.saved_searches.build(
        name: @form["name"].presence || automatic_name(definition),
        realm: definition.fetch("realm"),
        definition:,
        poll_interval_seconds: Integer(@form.fetch("poll_interval_seconds", "60")),
        cursor_sequence: @form["start_policy"] == "backfill" ? 0 : checkpoint,
        start_policy: @form.fetch("start_policy", "future_only"),
        notify_on_update: ActiveModel::Type::Boolean.new.cast(@form["notify_on_update"]),
        delivery_mode: @form.fetch("delivery_mode", "instant"),
        delivery_configuration:,
        timezone: "UTC",
        next_run_at: Time.current
      )

      if saved_search.save
        redirect_to admin_search_path, notice: "Saved search created."
      else
        @form_errors = saved_search.errors.full_messages
        load_page
        render :index, status: :unprocessable_entity
      end
    end

    def validate_webhook_url!(value)
      uri = URI.parse(value)
      raise ArgumentError, "Webhook URL must use HTTPS" unless uri.is_a?(URI::HTTPS) && uri.host.present?
    rescue URI::InvalidURIError
      raise ArgumentError, "Webhook URL is invalid"
    end

    def automatic_name(definition)
      realm = definition.fetch("realm").humanize
      subject = definition["text"].presence || "filtered search"
      "#{realm}: #{subject}".truncate(100)
    end

    def form_for(saved_search)
      definition = saved_search.definition
      form = DEFAULT_FORM.merge(
        "name" => saved_search.name,
        "realm" => saved_search.realm,
        "mode" => definition["mode"],
        "text" => definition["text"],
        "language" => definition["language"],
        "lexical_match" => definition["lexical_match"],
        "semantic_max_distance" => definition["semantic_max_distance"].to_s,
        "poll_interval_seconds" => saved_search.poll_interval_seconds.to_s,
        "start_policy" => saved_search.start_policy,
        "delivery_mode" => saved_search.delivery_mode,
        "notify_on_update" => saved_search.notify_on_update ? "1" : "0",
        "email" => Array(saved_search.delivery_configuration["channels"]).include?("email") ? "1" : "0",
        "webhook_url" => saved_search.delivery_configuration["webhook_url"],
        "digest_interval_seconds" => saved_search.delivery_configuration["digest_interval_seconds"].to_s
      )
      form["filters_json"] = JSON.pretty_generate(definition["filters"]) if definition["filters"]
      form
    end

    def render_error(message)
      @form_errors = [ message ]
      load_page
      render :index, status: :unprocessable_entity
    end

    def load_page
      @saved_searches = current_user.saved_searches.order(created_at: :desc)
      @publishers = Search::Media::FeedCatalog::PUBLISHERS.values.sort_by { |publisher| publisher.fetch("name") }
      @realm_contracts = Search::Realms.keys.index_with { |realm| Search::Realms.fetch(realm) }
      @search_namespace = Search::ProviderConfig.document_namespace
      @search_checkpoint = Searchable.checkpoint.to_i
      @searchable_record_count = Searchable.record_count
      @pending_search_sync_count = Searchable.pending_count
    end
  end
end
