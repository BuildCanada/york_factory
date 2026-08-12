class Metrics::SyncSubstackPostDetailsJob < Metrics::SubstackJob
  def perform(post, scheduled_for:)
    post.with_lock do
      return unless post.next_details_sync_at == scheduled_for
    end

    settings = settings_for(post.publication)
    raise Metrics::SubstackClient::AuthenticationError, "Substack auth cookies are missing" if settings[:cookies].blank?

    Metrics::SubstackAnalyticsSync.new(client: client_for(settings)).sync_post_details!(
      post,
      scheduled_for: scheduled_for
    )
    post.mark_details_synced!(scheduled_for: scheduled_for)
  end
end
