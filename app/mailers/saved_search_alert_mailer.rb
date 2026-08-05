class SavedSearchAlertMailer < ApplicationMailer
  def matches
    @batch = NotificationBatch.find(params.fetch(:batch_id))
    @payload = @batch.payload.deep_symbolize_keys
    mail(
      to: @batch.saved_search.user.email,
      subject: "#{@batch.saved_search.name}: #{@payload.fetch(:matches).length} new match#{'es' unless @payload.fetch(:matches).one?}"
    )
  end
end
