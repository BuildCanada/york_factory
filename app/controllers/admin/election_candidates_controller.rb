module Admin
  class ElectionCandidatesController < BaseController
    MAX_PHOTO_BYTES = 10.megabytes

    before_action :set_candidate

    def update
      if params[:warehouse_election_candidate]&.[](:purge_photo) == "1"
        @candidate.photo.purge
        @candidate.update!(photo_source: nil, photo_attribution: nil)
      end

      attrs = candidate_params
      attrs[:photo_source] = "manual" if attrs[:photo].present?
      @candidate.update!(attrs)

      redirect_back_to_election notice: "#{@candidate.display_name} updated."
    end

    # Accepts one of the machine-collected suggestions: downloads the image
    # server-side (so the admin's click is the review gate) and attaches it.
    def apply_photo_suggestion
      suggestion = @candidate.photo_suggestions.find { |s| s["image_url"] == params[:image_url] }
      unless suggestion
        return redirect_back_to_election alert: "Suggestion not found — it may have been refreshed."
      end

      io, content_type = download_image(suggestion["image_url"])
      filename = "#{@candidate.display_name.parameterize}#{Rack::Mime::MIME_TYPES.invert[content_type] || ".jpg"}"
      @candidate.photo.attach(io: io, filename: filename, content_type: content_type)
      @candidate.update!(
        photo_source: suggestion["source"],
        photo_attribution: suggestion["source"] == "wikipedia" ? "Wikipedia (#{suggestion["page_url"]})" : nil
      )

      redirect_back_to_election notice: "Photo attached for #{@candidate.display_name}."
    rescue => e
      redirect_back_to_election alert: "Could not fetch image: #{e.message}"
    end

    private

    def set_candidate
      @candidate = Warehouse::ElectionCandidate.find(params[:id])
    end

    def candidate_params
      params.require(:warehouse_election_candidate).permit(:photo, :photo_attribution)
    end

    def redirect_back_to_election(**flash)
      redirect_to admin_election_path(@candidate.race.election, anchor: "candidate-#{@candidate.id}"), **flash
    end

    def download_image(url)
      response = HTTPX.plugin(:follow_redirects).get(url)
      raise "HTTP #{response.status}" unless response.status == 200

      content_type = response.headers["content-type"].to_s.split(";").first
      raise "not an image (#{content_type})" unless content_type.start_with?("image/")

      body = response.body.to_s
      raise "image too large (#{body.bytesize} bytes)" if body.bytesize > MAX_PHOTO_BYTES

      [ StringIO.new(body), content_type ]
    end
  end
end
