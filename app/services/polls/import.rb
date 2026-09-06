module Polls
  class Import
    # Accept Surveyor's versioned export, never arbitrary model attributes.
    def self.call(bundle)
      unless bundle.is_a?(Hash) && bundle["kind"] == "buildcanada-poll-publication" && bundle["schemaVersion"] == 1
        raise ArgumentError, "Expected a Surveyor publication export (version 1)."
      end
      fields = bundle.fetch("memo")
      crosstabs = bundle.fetch("crosstabs")
      unless fields.is_a?(Hash) && crosstabs.is_a?(Hash) && crosstabs["schemaVersion"] == 2 &&
          crosstabs.dig("survey", "slug") == fields["survey_slug"] && crosstabs["tables"].is_a?(Array)
        raise ArgumentError, "Crosstabs must use Surveyor schema version 2 and match the survey."
      end
      allowed = (PollPublication::PARAMS - PollPublication::DOWNLOADS.map(&:to_sym)) +
        %i[slug title_en title_fr body_en body_fr appendix_en appendix_fr]
      memo = Memo.new(fields.slice(*allowed.map(&:to_s)))
      memo.content_kind = "poll"
      memo.publication = Memo::DEFAULT_PUBLICATION
      memo.published_at = nil
      memo.crosstabs_json.attach(io: StringIO.new(JSON.pretty_generate(crosstabs)),
        filename: "crosstabs.json", content_type: "application/json", identify: false)
      memo.save!
      memo
    rescue KeyError, TypeError
      raise ArgumentError, "The publication export must include memo and crosstabs objects."
    end
  end
end
