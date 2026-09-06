# Report assets and localized launch copy for Poll records.
module PollPublication
  extend ActiveSupport::Concern

  DOWNLOADS = %w[analysis_pdf_en analysis_pdf_fr crosstabs_pdf_en crosstabs_pdf_fr crosstabs_json].freeze
  PARAMS = %i[survey_slug survey_campaign_id pollster sample_size fieldwork_start fieldwork_end
    methodology_en methodology_fr news_release_en news_release_fr subscriber_email_en subscriber_email_fr
    email_subject_en email_subject_fr tweet_en tweet_fr].concat(DOWNLOADS.map(&:to_sym)).freeze

  included do
    DOWNLOADS.each { |name| has_one_attached name }
    has_localized_markdown :methodology
    has_localized_markdown :news_release
    has_localized_markdown :subscriber_email
    translates :email_subject, :tweet, backend: :column

    validates :survey_slug, presence: true
    validates :sample_size, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validate :validate_poll_files
    validate :validate_fieldwork_dates
  end

  def poll_downloads
    locale = I18n.locale == :fr ? "fr" : "en"
    downloads = %w[analysis_pdf crosstabs_pdf crosstabs_json].filter_map do |kind|
      name = kind == "crosstabs_json" ? kind : "#{kind}_#{locale}"
      name = "#{kind}_en" if kind != "crosstabs_json" && !public_send(name).attached?
      [ kind, name ] if public_send(name).attached?
    end.to_h
    downloads["analysis_markdown"] = "analysis_markdown" if body.present?
    downloads
  end

  private

  def validate_poll_files
    DOWNLOADS.each do |name|
      attachment = public_send(name)
      next unless attachment.attached?
      expected = name == "crosstabs_json" ? "application/json" : "application/pdf"
      errors.add(name, "must be #{expected}") unless attachment.blob.content_type == expected
      errors.add(name, "must be smaller than 100 MB") if attachment.blob.byte_size > 100.megabytes
    end
  end

  def validate_fieldwork_dates
    if fieldwork_start && fieldwork_end && fieldwork_end < fieldwork_start
      errors.add(:fieldwork_end, "must be on or after the start date")
    end
  end
end
