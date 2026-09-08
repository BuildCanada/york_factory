module Polls
  class GenerateArtifactsJob < ApplicationJob
    queue_as :default
    limits_concurrency to: 1, key: ->(poll_id) { poll_id }, duration: 5.minutes
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(poll_id)
      failures = []
      PollArtifacts::GENERATED.each do |name|
        poll = Poll.find_by(id: poll_id)
        return unless poll
        digest = poll.artifact_digest(name)
        next if digest.blank? || poll.artifact_current?(name)
        blob = nil
        begin
          bytes = name == "crosstabs_xlsx" ? CrosstabsWorkbook.new(poll).render : AnalysisPdf.new(poll, name.last(2)).render
          blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: poll.download_filename(name),
            content_type: name == "crosstabs_xlsx" ? PollArtifacts::XLSX_TYPE : "application/pdf",
            identify: false, metadata: { source_digest: digest })
          poll.with_lock do
            if poll.artifact_digest(name) == digest
              poll.suppress_artifact_enqueue = true
              poll.public_send("#{name}=", blob)
              poll.save!
              poll.update_columns(artifact_errors: poll.artifact_errors.except(name))
              blob = nil
            end
          end
        rescue StandardError => e
          poll.with_lock do
            if poll.artifact_digest(name) == digest
              poll.update_columns(artifact_errors: poll.artifact_errors.merge(name => { "digest" => digest, "message" => e.message.truncate(500) }))
            end
          end
          failures << e
        ensure
          blob&.purge_later
        end
      end
      raise failures.first if failures.any?
    end
  end
end
