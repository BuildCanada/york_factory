class GovernmentEntity::EntityResolver < ActiveRecord::AssociatedObject
  # Entity resolution cascade:
  #   1. Exact match on government_entity_aliases.alias_name
  #   2. Case-insensitive match
  #   3. Encoding normalization (curly quotes → straight)
  #   4. LLM fuzzy match with top 5 candidates
  #   5. Confidence gate (>= 0.8 auto-accept, < 0.8 flag for review)

  Result = Data.define(:government_entity, :lineage_entry)

  def resolve(name:, raw_ingestion: nil)
    # Step 1: Exact match
    alias_record = GovernmentEntityAlias.find_by(alias_name: name)
    if alias_record
      entry = create_lineage(raw_ingestion, name, alias_record.government_entity, "exact_match", 1.0)
      return Result.new(government_entity: alias_record.government_entity, lineage_entry: entry)
    end

    # Step 2: Case-insensitive match
    alias_record = GovernmentEntityAlias.where("LOWER(alias_name) = LOWER(?)", name).first
    if alias_record
      entry = create_lineage(raw_ingestion, name, alias_record.government_entity, "case_insensitive", 0.99)
      return Result.new(government_entity: alias_record.government_entity, lineage_entry: entry)
    end

    # Step 3: Encoding normalization
    normalized = normalize_encoding(name)
    if normalized != name
      alias_record = GovernmentEntityAlias.find_by(alias_name: normalized)
      if alias_record
        # Add the original name as a new alias for future exact matches
        alias_record.government_entity.government_entity_aliases.find_or_create_by!(alias_name: name)
        entry = create_lineage(raw_ingestion, name, alias_record.government_entity, "encoding_normalized", 0.95)
        return Result.new(government_entity: alias_record.government_entity, lineage_entry: entry)
      end
    end

    # Step 4: LLM fuzzy match
    llm_resolve(name: name, raw_ingestion: raw_ingestion)
  end

  # Resolve by InfoBase org_id — deterministic, no LLM needed
  def resolve_by_infobase_id(org_id:, org_name:, raw_ingestion: nil)
    entity = GovernmentEntity.find_by(org_id_infobase: org_id)

    unless entity
      entity = GovernmentEntity.create!(canonical_name: org_name, org_id_infobase: org_id)
    end

    # Ensure alias exists for this name
    entity.government_entity_aliases.find_or_create_by!(alias_name: org_name)

    entry = create_lineage(raw_ingestion, org_name, entity, "deterministic", 1.0)
    Result.new(government_entity: entity, lineage_entry: entry)
  end

  private

  def normalize_encoding(name)
    # Replace curly/smart quotes with straight quotes (byte 0x92 → 0x27)
    name
      .gsub("\u2018", "'")  # left single quote
      .gsub("\u2019", "'")  # right single quote
      .gsub("\u201C", '"')  # left double quote
      .gsub("\u201D", '"')  # right double quote
      .gsub("\u0092", "'")  # Windows-1252 right single quote
      .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      .strip
  end

  def llm_resolve(name:, raw_ingestion:)
    candidates = find_candidates(name)

    if candidates.empty?
      entry = create_lineage(raw_ingestion, name, nil, "skipped", 0.0)
      return Result.new(government_entity: nil, lineage_entry: entry)
    end

    result = llm_call_with_retry(name, candidates)

    if result[:match].nil? || result[:confidence] < 0.1
      # Create as new entity flagged for human review
      entity = GovernmentEntity.find_or_create_by!(canonical_name: name) do |e|
        e.needs_review = true
      end
      entity.government_entity_aliases.find_or_create_by!(alias_name: name)
      entry = create_lineage(raw_ingestion, name, entity, "auto_created_for_review", 0.0,
        llm_prompt: result[:raw_prompt], llm_response: result[:raw_response])
      return Result.new(government_entity: entity, lineage_entry: entry)
    end

    matched_entity = GovernmentEntity.find_by(canonical_name: result[:match])
    return Result.new(government_entity: nil, lineage_entry: create_lineage(raw_ingestion, name, nil, "skipped", 0.0)) unless matched_entity

    confidence = result[:confidence]

    # Auto-accept high confidence: create alias for future exact matches
    if confidence >= 0.8
      matched_entity.government_entity_aliases.find_or_create_by!(alias_name: name)
    end

    entry = create_lineage(
      raw_ingestion, name, matched_entity, "llm_fuzzy", confidence,
      llm_model: LlmClient::MODEL,
      llm_prompt: result[:raw_prompt],
      llm_response: result[:raw_response]
    )

    Result.new(government_entity: matched_entity, lineage_entry: entry)
  end

  def llm_call_with_retry(name, candidates)
    result = LlmClient.instance.entity_resolve(org_name: name, candidates: candidates.map(&:canonical_name))

    if result[:match].nil? && result[:confidence] == 0.0
      # Retry once on failure
      result = LlmClient.instance.entity_resolve(org_name: name, candidates: candidates.map(&:canonical_name))
    end

    result
  end

  def find_candidates(name)
    # Find top 5 candidates by substring overlap (simple heuristic)
    # In production, could use pg_trgm for better similarity search
    all_entities = GovernmentEntity.pluck(:id, :canonical_name)
    scored = all_entities.map do |id, canonical|
      score = levenshtein_similarity(name.downcase, canonical.downcase)
      [id, canonical, score]
    end
    scored.sort_by { |_, _, s| -s }.first(5).map { |id, cn, _| GovernmentEntity.new(id: id, canonical_name: cn) }
  end

  def levenshtein_similarity(a, b)
    # Simple similarity based on shared character n-grams
    return 1.0 if a == b
    return 0.0 if a.empty? || b.empty?

    trigrams_a = (0..a.length - 3).map { |i| a[i, 3] }.to_set
    trigrams_b = (0..b.length - 3).map { |i| b[i, 3] }.to_set

    return 0.0 if trigrams_a.empty? || trigrams_b.empty?

    intersection = (trigrams_a & trigrams_b).size.to_f
    union = (trigrams_a | trigrams_b).size.to_f

    intersection / union
  end

  def create_lineage(raw_ingestion, source_value, entity, transformation_type, confidence, llm_model: nil, llm_prompt: nil, llm_response: nil)
    LineageEntry.create!(
      raw_ingestion: raw_ingestion,
      source_field: "government_entity_name",
      source_value: source_value,
      target_field: "government_entity_id",
      target_value: entity&.id&.to_s,
      transformation_type: transformation_type,
      confidence: confidence,
      llm_model: llm_model,
      llm_prompt_snapshot: llm_prompt ? { prompt: llm_prompt } : nil,
      llm_response_snapshot: llm_response ? { response: llm_response } : nil
    )
  end
end
