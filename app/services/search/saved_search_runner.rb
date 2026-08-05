module Search
  class SavedSearchRunner
    CANDIDATE_LIMIT = 500

    class CandidateLimitExceeded < StandardError; end

    def initialize(run, query_runner: Search::QueryRunner.new)
      @run = run
      @saved_search = run.saved_search
      @query_runner = query_runner
      @query_count = 0
      @billing = {}
      @performance = {}
    end

    def call
      @run.start!
      matches = evaluate_range(@run.from_sequence, @run.to_sequence)
      persisted, inserted_count = persist_matches(matches)
      route_matches(persisted)

      SavedSearch.transaction do
        @saved_search.update!(cursor_sequence: @run.to_sequence)
        @run.succeed!(
          query_count: @query_count,
          matched_count: inserted_count,
          billing: @billing,
          performance: @performance
        )
      end

      persisted
    rescue => error
      @run.fail!(error: "#{error.class}: #{error.message}") if @run.persisted?
      raise
    end

    private

    def evaluate_range(from_sequence, to_sequence)
      return [] if to_sequence <= from_sequence

      result = execute(from_sequence:, to_sequence:)
      if result.rows.length >= CANDIDATE_LIMIT && to_sequence - from_sequence <= 1
        raise CandidateLimitExceeded,
          "index sequence #{to_sequence} returned at least #{CANDIDATE_LIMIT} candidates"
      end
      if result.rows.length >= CANDIDATE_LIMIT
        midpoint = from_sequence + ((to_sequence - from_sequence) / 2)
        return evaluate_range(from_sequence, midpoint) + evaluate_range(midpoint, to_sequence)
      end
      result.rows
    end

    def execute(from_sequence: nil, to_sequence: nil, evaluated_at: Time.current)
      result = @query_runner.call(
        @saved_search.definition,
        realm: @saved_search.realm,
        from_sequence:,
        to_sequence:,
        evaluated_at:,
        limit: CANDIDATE_LIMIT
      )
      @query_count += result.query_count
      @billing = merge_metrics(@billing, result.billing)
      @performance = merge_metrics(@performance, result.performance)
      result
    end

    def persist_matches(rows)
      searchables = resolve_searchables(rows.filter_map { |row| row[:id] || row["id"] })
      inserted_count = 0
      matches = rows.filter_map do |row|
        index_id = (row[:id] || row["id"]).to_s
        searchable = searchables[index_id]
        next unless searchable

        match = SavedSearchMatch.new(
          saved_search: @saved_search,
          searchable: searchable,
          match_evidence: evidence(row)
        )
        match.save!
        inserted_count += 1
        match
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
        raise unless duplicate_match?(error, match)

        @saved_search.matches.find_by!(match_key: match.match_key)
      end
      [ matches.uniq(&:id), inserted_count ]
    end

    def resolve_searchables(index_ids)
      index_ids.index_with { |index_id| Searchable.resolve(index_id.to_s) }.compact
    end

    def duplicate_match?(error, match)
      error.is_a?(ActiveRecord::RecordNotUnique) || match.errors.of_kind?(:match_key, :taken)
    end

    def evidence(row)
      distance = row[:"$dist"] || row["$dist"]
      { "semantic_distance" => distance }.compact
    end

    def route_matches(matches)
      matches.each do |match|
        if @saved_search.delivery_mode == "instant"
          close_instant_batch(match)
        else
          buffer_digest_match(match)
        end
      end
    end

    def close_instant_batch(match)
      batch = nil
      NotificationBatch.transaction do
        match.lock!
        batch = match.notification_batch
        unless batch
          batch = NotificationBatch.create!(
            saved_search: @saved_search,
            mode: "instant",
            state: "open"
          )
          match.update!(notification_batch: batch)
        end
        batch.close! if batch.state == "open"
        match.update!(state: match_state_for(batch))
      end

      batch.notification_deliveries.where(status: %w[pending failed]).find_each do |delivery|
        Search::DeliverNotificationJob.perform_later(delivery.id)
      end
    end

    def buffer_digest_match(match)
      batch = nil
      NotificationBatch.transaction do
        match.lock!
        batch = match.notification_batch
        unless batch
          @saved_search.with_lock do
            batch = NotificationBatch.find_or_create_by!(
              saved_search: @saved_search,
              mode: "digest",
              state: "open"
            ) do |record|
              record.scheduled_for = next_digest_at
            end
          end
          match.update!(notification_batch: batch, state: "buffered")
        end
      end
      Search::DeliverDigestJob.set(wait_until: batch.scheduled_for).perform_later(batch.id) if batch.state == "open"
    end

    def match_state_for(batch)
      case batch.state
      when "delivered" then "delivered"
      when "dead" then "dead"
      else "dispatching"
      end
    end

    def next_digest_at
      seconds = @saved_search.delivery_configuration.fetch("digest_interval_seconds", 1.hour.to_i).to_i
      Time.current + seconds.clamp(1.hour.to_i, 1.week.to_i)
    end

    def merge_metrics(left, right)
      left.to_h.merge(right.to_h) do |_key, old_value, new_value|
        old_value.is_a?(Numeric) && new_value.is_a?(Numeric) ? old_value + new_value : new_value
      end
    end
  end
end
