module Admin
  class MediaClipsController < BaseController
    include ActiveStorage::SetCurrent

    def create
      recording = Warehouse::MediaRecording.find(params[:recording_id])
      attributes = params.require(:media_clip).permit(:title, :start_offset, :end_offset, :audio_track_id, :export_mode, caption_languages: [])
      start_offset = Float(attributes.fetch(:start_offset))
      end_offset = Float(attributes.fetch(:end_offset))
      unless start_offset.finite? && end_offset.finite? && start_offset >= 0 && end_offset > start_offset && end_offset - start_offset <= 30.minutes
        raise ArgumentError, "Select a clip between 0 and 30 minutes long."
      end
      track = recording.stream.tracks.where(kind: "audio").find(attributes[:audio_track_id]) if attributes[:audio_track_id].present?
      clip = MediaClip.create!(user: current_user, recording: recording, track: track,
        title: attributes[:title].presence || "Clip from #{recording.title_en}", state: "queued",
        starts_at: recording.starts_at + start_offset, ends_at: recording.starts_at + end_offset,
        metadata: {
          "caption_languages" => Array(attributes[:caption_languages]).intersection(%w[en fr]),
          "export_mode" => attributes[:export_mode].presence || "exact"
        })
      clip.export_later
      notice = if clip.export_mode == "exact"
        "Precise clip export queued. The exported boundaries will match your selection within one frame."
      else
        "Fast copy export queued. Exported boundaries may expand to nearby keyframes."
      end
      redirect_to admin_media_clip_path(clip), notice:
    rescue ActiveRecord::RecordInvalid => error
      redirect_to admin_broadcast_path(recording), alert: error.record.errors.full_messages.to_sentence
    rescue ArgumentError, KeyError => error
      redirect_to admin_broadcast_path(recording), alert: error.message
    end

    def show
      @clip = MediaClip.where(user: current_user).find(params[:id])
    end

    def retry_export
      clip = MediaClip.where(user: current_user).find(params[:id])
      queued = clip.with_lock do
        next false unless clip.state == "failed"

        clip.update!(state: "queued", error: nil)
        true
      end
      clip.export_later if queued
      redirect_to admin_media_clip_path(clip), notice: queued ? "Export queued again." : "Export is already active or complete."
    end

    def download
      clip = MediaClip.where(user: current_user).find(params[:id])
      return head :not_found unless clip.state == "ready"

      attachment = params[:caption_id].present? ? clip.captions_attachments.find(params[:caption_id]) : clip.file
      return head :not_found unless attachment.respond_to?(:blob) && attachment.blob

      disposition = params[:disposition] == "inline" ? "inline" : "attachment"
      redirect_to attachment.blob.url(expires_in: 5.minutes, disposition:), allow_other_host: true
    end
  end
end
