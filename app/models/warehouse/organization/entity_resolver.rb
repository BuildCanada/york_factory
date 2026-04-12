class Warehouse::Organization::EntityResolver < ActiveRecord::AssociatedObject
  # Entity resolution cascade:
  #   1. Exact match on organization_aliases.alias_name
  #   2. Case-insensitive match
  #   3. Encoding normalization (curly quotes -> straight)
  #   4. LLM fuzzy match with top 5 candidates
  #   5. Confidence gate (>= 0.8 auto-accept, < 0.8 flag for review)

  LLM_MODEL = "claude-haiku-4-5-20251001"
  MAX_LLM_CALLS = 1000

  Result = Data.define(:organization, :lineage_entry)

  def resolve(name:, raw_ingestion: nil)
    # Step 1: Exact match
    alias_record = Warehouse::OrganizationAlias.find_by(alias_name: name)
    if alias_record
      entry = create_lineage(raw_ingestion, name, alias_record.organization, "exact_match", 1.0)
      return Result.new(organization: alias_record.organization, lineage_entry: entry)
    end

    # Step 2: Case-insensitive match
    alias_record = Warehouse::OrganizationAlias.where("LOWER(alias_name) = LOWER(?)", name).first
    if alias_record
      entry = create_lineage(raw_ingestion, name, alias_record.organization, "case_insensitive", 0.99)
      return Result.new(organization: alias_record.organization, lineage_entry: entry)
    end

    # Step 3: Encoding normalization
    normalized = normalize_encoding(name)
    if normalized != name
      alias_record = Warehouse::OrganizationAlias.find_by(alias_name: normalized)
      if alias_record
        # Add the original name as a new alias for future exact matches
        alias_record.organization.organization_aliases.find_or_create_by!(alias_name: name)
        entry = create_lineage(raw_ingestion, name, alias_record.organization, "encoding_normalized", 0.95)
        return Result.new(organization: alias_record.organization, lineage_entry: entry)
      end
    end

    # Step 4: LLM fuzzy match
    llm_resolve(name: name, raw_ingestion: raw_ingestion)
  end

  # Resolve by InfoBase org_id -- deterministic, no LLM needed
  def resolve_by_infobase_id(org_id:, org_name:, raw_ingestion: nil)
    org = Warehouse::Organization.find_by(org_id_infobase: org_id)

    unless org
      org = Warehouse::Organization.create!(canonical_name: org_name, org_id_infobase: org_id)
    end

    # Ensure alias exists for this name
    org.organization_aliases.find_or_create_by!(alias_name: org_name)

    entry = create_lineage(raw_ingestion, org_name, org, "deterministic", 1.0)
    Result.new(organization: org, lineage_entry: entry)
  end

  def reset_llm_call_count!
    @llm_call_count = 0
  end

  private

  def normalize_encoding(name)
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
      return Result.new(organization: nil, lineage_entry: entry)
    end

    result = llm_entity_resolve(name, candidates.map(&:canonical_name))

    # Retry once on failure
    if result[:match].nil? && result[:confidence] == 0.0
      result = llm_entity_resolve(name, candidates.map(&:canonical_name))
    end

    if result[:match].nil? || result[:confidence] < 0.1
      # Create as new org flagged for human review
      org = Warehouse::Organization.find_or_create_by!(canonical_name: name) do |o|
        o.needs_review = true
      end
      org.organization_aliases.find_or_create_by!(alias_name: name)
      entry = create_lineage(raw_ingestion, name, org, "auto_created_for_review", 0.0,
        llm_prompt: result[:raw_prompt], llm_response: result[:raw_response])
      return Result.new(organization: org, lineage_entry: entry)
    end

    matched_org = Warehouse::Organization.find_by(canonical_name: result[:match])
    return Result.new(organization: nil, lineage_entry: create_lineage(raw_ingestion, name, nil, "skipped", 0.0)) unless matched_org

    confidence = result[:confidence]

    # Auto-accept high confidence: create alias for future exact matches
    if confidence >= 0.8
      matched_org.organization_aliases.find_or_create_by!(alias_name: name)
    end

    entry = create_lineage(
      raw_ingestion, name, matched_org, "llm_fuzzy", confidence,
      llm_model: LLM_MODEL,
      llm_prompt: result[:raw_prompt],
      llm_response: result[:raw_response]
    )

    Result.new(organization: matched_org, lineage_entry: entry)
  end

  def llm_entity_resolve(org_name, candidate_names)
    @llm_call_count ||= 0
    raise "LLM call limit exceeded (#{MAX_LLM_CALLS})" if @llm_call_count >= MAX_LLM_CALLS
    @llm_call_count += 1

    candidate_list = candidate_names.map.with_index { |c, i| "#{i + 1}. #{c}" }.join("\n")

    prompt = <<~PROMPT
      You are matching a government organization name from a budget document to a list of canonical organization names.

      Organization name to match: "#{org_name}"

      Candidate canonical names:
      #{candidate_list}

      Respond with JSON only:
      {
        "match": "exact canonical name from the list above, or null if no match",
        "confidence": 0.0 to 1.0,
        "reasoning": "brief explanation"
      }

      If none of the candidates are a reasonable match, set match to null and confidence to 0.
    PROMPT

    text = RubyLLM.chat(model: LLM_MODEL).ask(prompt).content.strip
    parsed = JSON.parse(text)

    {
      match: parsed["match"],
      confidence: parsed["confidence"].to_f,
      reasoning: parsed["reasoning"],
      raw_prompt: prompt,
      raw_response: text
    }
  rescue JSON::ParserError => e
    { match: nil, confidence: 0.0, reasoning: "Failed to parse LLM response: #{e.message}", raw_prompt: prompt, raw_response: text }
  rescue => e
    { match: nil, confidence: 0.0, reasoning: "LLM API error: #{e.message}", raw_prompt: prompt, raw_response: nil }
  end

  def find_candidates(name)
    # Find top 5 candidates by substring overlap (simple heuristic)
    # In production, could use pg_trgm for better similarity search
    all_orgs = Warehouse::Organization.pluck(:id, :canonical_name)
    scored = all_orgs.map do |id, canonical|
      score = trigram_similarity(name.downcase, canonical.downcase)
      [ id, canonical, score ]
    end
    scored.sort_by { |_, _, s| -s }.first(5).map { |id, cn, _| Warehouse::Organization.new(id: id, canonical_name: cn) }
  end

  def trigram_similarity(a, b)
    return 1.0 if a == b
    return 0.0 if a.empty? || b.empty?

    trigrams_a = (0..a.length - 3).map { |i| a[i, 3] }.to_set
    trigrams_b = (0..b.length - 3).map { |i| b[i, 3] }.to_set

    return 0.0 if trigrams_a.empty? || trigrams_b.empty?

    intersection = (trigrams_a & trigrams_b).size.to_f
    union = (trigrams_a | trigrams_b).size.to_f

    intersection / union
  end

  def create_lineage(raw_ingestion, source_value, org, transformation_type, confidence, llm_model: nil, llm_prompt: nil, llm_response: nil)
    Warehouse::LineageEntry.create!(
      raw_ingestion: raw_ingestion,
      source_field: "organization_name",
      source_value: source_value,
      target_field: "organization_id",
      target_value: org&.id&.to_s,
      transformation_type: transformation_type,
      confidence: confidence,
      llm_model: llm_model,
      llm_prompt_snapshot: llm_prompt ? { prompt: llm_prompt } : nil,
      llm_response_snapshot: llm_response ? { response: llm_response } : nil
    )
  end
end
