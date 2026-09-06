module PollArtifacts
  extend ActiveSupport::Concern
  GENERATED = %w[analysis_pdf_en analysis_pdf_fr crosstabs_xlsx].freeze
  XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  VERSION = 5

  included do
    has_one_attached :crosstabs_xlsx
    attr_accessor :suppress_artifact_enqueue
    after_commit :enqueue_poll_artifacts, on: [ :create, :update ]
  end

  def artifact_digest(name)
    common = [ VERSION, title_en, title_fr, published_at&.iso8601, slug ]
    if name == "crosstabs_xlsx"
      return unless crosstabs_json.attached?
      common << crosstabs_json.blob.checksum
    else
      locale = name.end_with?("_fr") ? "fr" : "en"
      return if public_send("body_#{locale}").blank?
      common.concat([ survey_scope, locale, public_send("body_#{locale}"), public_send("appendix_#{locale}"),
        public_send("methodology_#{locale}"), public_send("key_messages_#{locale}").presence || key_messages_en, pollster, sample_size,
        fieldwork_start, fieldwork_end, author&.name, author_name ])
    end
    Digest::SHA256.hexdigest(common.to_json)
  end

  def artifact_current?(name)
    attachment = public_send(name)
    digest = artifact_digest(name)
    digest.present? && attachment.attached? && attachment.blob.metadata["source_digest"] == digest
  end

  def download_filename(name)
    locale = name.end_with?("_fr") ? :fr : :en
    title = public_send("title_#{locale}").presence || title_en.presence || slug
    title = title.gsub(/[\\\/:*?"<>|\r\n]/, " ").squish.truncate(140, omission: "")
    date = published_at&.to_date&.iso8601 || "Draft"
    suffix = name.start_with?("analysis") ? "Report#{locale == :fr ? ' FR' : ''}" : "Crosstabs"
    ext = name == "crosstabs_json" ? "json" : name == "crosstabs_xlsx" ? "xlsx" : name == "analysis_markdown" ? "md" : "pdf"
    "Build Canada - #{date} - #{title} - #{suffix}.#{ext}"
  end

  private

  def enqueue_poll_artifacts
    return if suppress_artifact_enqueue
    if GENERATED.any? { |name| artifact_digest(name).present? && !artifact_current?(name) }
      Polls::GenerateArtifactsJob.perform_later(id)
    end
  end
end
