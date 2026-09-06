module Polls
  class Import
    # Accept Surveyor's versioned export, never arbitrary model attributes.
    def self.call(bundle)
      unless bundle.is_a?(Hash) && bundle["kind"] == "buildcanada-poll-publication" && bundle["schemaVersion"] == 1
        raise ArgumentError, "Expected a Surveyor publication export (version 1)."
      end
      fields = bundle.fetch("poll")
      crosstabs = bundle.fetch("crosstabs")
      unless fields.is_a?(Hash) && crosstabs.is_a?(Hash) && crosstabs["schemaVersion"] == 2 &&
          crosstabs.dig("survey", "slug") == fields["survey_slug"] && crosstabs["tables"].is_a?(Array)
        raise ArgumentError, "Crosstabs must use Surveyor schema version 2 and match the survey."
      end
      allowed = (PollPublication::PARAMS - PollPublication::DOWNLOADS.map(&:to_sym)) +
        %i[slug title_en title_fr body_en body_fr appendix_en appendix_fr]
      poll = Poll.new(fields.slice(*allowed.map(&:to_s)))
      poll.published_at = nil
      poll.crosstabs_json.attach(io: StringIO.new(JSON.pretty_generate(crosstabs)),
        filename: "crosstabs.json", content_type: "application/json", identify: false)
      poll.save!
      poll
    rescue KeyError, TypeError
      raise ArgumentError, "The publication export must include poll and crosstabs objects."
    end
  end
end
