module Warehouse::Broadcasts
  class CaptionPresentation
    def initialize(track, starts_at:, ends_at:, storage: nil)
      @track, @starts_at, @ends_at, @storage = track, starts_at, ends_at, storage
    end

    def call
      return "WEBVTT\n\n" unless @ends_at > @starts_at
      raise ArgumentError, "caption window is too large" if @ends_at - @starts_at > 35.minutes

      objects = @track.objects.where(kind: "caption_file").overlapping(@starts_at, @ends_at).order(:starts_at, :id).limit(100).to_a
      cache_key = [ "broadcast-vtt-v1", @track.id, @starts_at.to_f, @ends_at.to_f, objects.map(&:checksum) ]
      Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
        cues = objects.flat_map do |object|
          offset = object.starts_at - @starts_at
          WebVtt.parse(storage.download(key: object.object_key)).map do |cue|
            cue.with(start_seconds: cue.start_seconds + offset, end_seconds: cue.end_seconds + offset)
          end
        end
        cues = cues.sort_by(&:start_seconds).uniq { |cue| [ cue.start_seconds, cue.end_seconds, cue.text ] }
        WebVtt.render(WebVtt.clip(cues, from: 0, to: @ends_at - @starts_at))
      end
    end

    private

    def storage
      @storage ||= Storage.new
    end
  end
end
