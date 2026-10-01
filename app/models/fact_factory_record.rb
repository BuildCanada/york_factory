# Base class for fact-factory's tables (docs/public-interface-design.md §5.2 and
# §5.3). The public data API reads the fact_factory schema directly as the
# read-only role api_reader: the registry, spending, derived and elections
# tables, with no copy and no read model. The schema is fact-factory's
# (db/fact_factory/schema.sql is a vendored copy), not ours: Rails never
# migrates, dumps or writes it. The connection is read-only twice over: every
# transaction is read-only (database.yml, and the role), and these models refuse
# to save.
#
# Registry and derived tables are versioned by registry revision: a row is
# current as of revision N when revision_id <= N and (retired_revision_id IS
# NULL or retired_revision_id > N). Query them through the FactFactory query
# objects, which the REST controllers and the MCP server share.
class FactFactoryRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :fact_factory, reading: :fact_factory }

  SCHEMA_NAME = /\A[a-z_][a-z0-9_]*\z/

  # The schema fact-factory's tables are in (FACT_FACTORY_DB_SCHEMA, as in
  # fact-factory; default fact_factory).
  def self.schema
    @schema ||= ENV.fetch("FACT_FACTORY_DB_SCHEMA", "fact_factory").tap do |name|
      raise ArgumentError, "FACT_FACTORY_DB_SCHEMA must be a plain identifier, not #{name.inspect}" unless name.match?(SCHEMA_NAME)
    end
  end

  # A fact-factory table, schema-qualified, for SQL.
  def self.table(name) = "#{schema}.#{name}"

  # SQL for "this version is current as of revision :n" on a table alias.
  def self.as_of(table_alias = nil, param: "n")
    prefix = table_alias ? "#{table_alias}." : ""
    "#{prefix}revision_id <= :#{param} AND (#{prefix}retired_revision_id IS NULL OR #{prefix}retired_revision_id > :#{param})"
  end

  def readonly? = true
end
