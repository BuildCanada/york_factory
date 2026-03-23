class NaturalLanguageQuery
  QUERY_TIMEOUT = 10 # seconds
  MAX_ROWS = 1000
  MUTATION_PATTERN = /\b(INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|CREATE|GRANT|REVOKE)\b/i

  SCHEMA_DESCRIPTION = <<~SCHEMA
    government_entities (id, canonical_name, org_id_infobase)
    government_entity_aliases (id, government_entity_id, alias_name, valid_from, valid_to)
    fiscal_authorities (id, government_entity_id, fiscal_year, document_type [main/supp_a/supp_b/supp_c], vote_number, vote_type [operating/capital/grants_contributions/statutory], description, amount)
    fiscal_expenditures (id, government_entity_id, fiscal_year, vote_number, vote_type, description, pa_voted_ceiling, actual_expenditure)
    spending_deviations (government_entity_id, fiscal_year, vote_number, vote_type, consolidated_estimate, actual_expenditure, variance_amount, variance_pct) — this is a VIEW
    standard_object_expenditures (id, government_entity_id, fiscal_year, standard_object, amount)
    lobbyists (id, name, registration_number, lobbyist_type)
    lobbying_activities (id, lobbyist_id, government_entity_id, client_name, subject_matter, start_date, end_date, status)
    corporate_entities (id, jurisdiction [federal/bc/qc/on/ab/sk/etc], registry_id, business_number, legal_name, corporation_type, status, registered_office_province, incorporation_date, dissolution_date, source_system, government_entity_id)
    corporate_entity_aliases (id, corporate_entity_id, alias_name, effective_date, expiry_date)
    corporate_directors (id, full_name, normalized_name, province, postal_code)
    director_appointments (id, corporate_entity_id, corporate_director_id, appointed_date, ceased_date, role)
    corporate_registrations (id, corporate_entity_id, event_type, event_date, description)
    business_establishments (id, business_name, trade_name, business_number, naics_code, naics_description, employee_size_range, address, city, province, postal_code, corporate_entity_id)
    standardized_addresses (id, full_address, street_name, street_number, city, province, postal_code, latitude, longitude, source_id)

    fiscal_year is a string in "YYYY-YY" format (e.g., "2023-24").
    Government entities are linked to their fiscal data via government_entity_id.
    Use government_entity_aliases to match alternative names.
    spending_deviations shows planned vs actual: variance_pct > 20 means significant overspend.
    corporate_entities tracks registered corporations across all Canadian jurisdictions.
    business_establishments (from ODBiz) links to corporate_entities via business_number.
    director_appointments is a temporal join: use appointed_date/ceased_date to find current directors.
    To find directors on multiple boards: GROUP BY corporate_director_id HAVING COUNT(*) > 1.
  SCHEMA

  def ask(question)
    result = LlmClient.instance.generate_sql(
      question: question,
      schema_description: SCHEMA_DESCRIPTION
    )

    return { error: result[:explanation] } if result[:sql].nil?

    sql = result[:sql]

    if MUTATION_PATTERN.match?(sql)
      return { error: "Query rejected: only SELECT queries are allowed" }
    end

    # Add LIMIT if not present
    unless sql.match?(/\bLIMIT\b/i)
      sql = "#{sql.chomp(';')} LIMIT #{MAX_ROWS};"
    end

    rows = execute_with_timeout(sql)

    {
      question: question,
      sql: sql,
      explanation: result[:explanation],
      results: rows,
      row_count: rows.length
    }
  rescue ActiveRecord::StatementInvalid => e
    { error: "SQL error: #{e.message}", sql: sql }
  end

  private

  def execute_with_timeout(sql)
    ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = '#{QUERY_TIMEOUT}s'")
    ActiveRecord::Base.connection.select_all(sql).to_a
  end
end
