# Downloads York Factory used to generate for polls (an analysis PDF per locale
# and a crosstabs workbook). Nothing is generated any more: a poll's report is
# the Report PDF uploaded from Surveyor. Files older polls already have are kept
# and still served, and editors can remove them.
module PollArtifacts
  extend ActiveSupport::Concern
  GENERATED = %w[analysis_pdf_en analysis_pdf_fr crosstabs_xlsx].freeze
  XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

  included do
    has_one_attached :crosstabs_xlsx
  end

  def download_filename(name)
    locale = name.end_with?("_fr") ? :fr : :en
    title = public_send("title_#{locale}").presence || title_en.presence || slug
    title = title.gsub(/[\\\/:*?"<>|\r\n]/, " ").squish.truncate(140, omission: "")
    date = published_at&.to_date&.iso8601 || "Draft"
    suffix = name.start_with?("analysis", "report") ? "Report#{locale == :fr ? ' FR' : ''}" : "Crosstabs"
    ext = name == "crosstabs_json" ? "json" : name == "crosstabs_xlsx" ? "xlsx" : name == "analysis_markdown" ? "md" : "pdf"
    "Build Canada - #{date} - #{title} - #{suffix}.#{ext}"
  end
end
