class NaturalLanguageQuery
  QUERY_TIMEOUT = 10 # seconds
  MAX_ROWS = 1000
  MUTATION_PATTERN = /\b(INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|CREATE|GRANT|REVOKE)\b/i

  SCHEMA_DESCRIPTION = <<~SCHEMA
    organizations (id, canonical_name, org_id_infobase)
    organization_aliases (id, organization_id, alias_name, valid_from, valid_to)
    fiscal_authorities (id, organization_id, fiscal_year, document_type [main/supp_a/supp_b/supp_c], vote_number, vote_type [operating/capital/grants_contributions/statutory], description, amount)
    fiscal_expenditures (id, organization_id, fiscal_year, vote_number, vote_type, description, pa_voted_ceiling, actual_expenditure)
    spending_deviations (organization_id, fiscal_year, vote_number, vote_type, consolidated_estimate, actual_expenditure, variance_amount, variance_pct) — this is a VIEW
    standard_object_expenditures (id, organization_id, fiscal_year, standard_object, amount)
    lobbyists (id, name, registration_number, lobbyist_type)
    lobbying_activities (id, lobbyist_id, organization_id, client_name, subject_matter, start_date, end_date, status)

    fiscal_year is a string in "YYYY-YY" format (e.g., "2023-24").
    Organizations are linked to their fiscal data via organization_id.
    Use organization_aliases to match alternative names.
    spending_deviations shows planned vs actual: variance_pct > 20 means significant overspend.
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
