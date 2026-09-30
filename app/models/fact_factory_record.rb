# Base class for fact-factory's `api` read model (docs/public-interface-design.md
# §5.2 and §5.3): the allowlisted, release-versioned tables the public data API
# serves. The schema is fact-factory's (serve/api_schema.sql), not ours: Rails
# never migrates, dumps or writes it. The connection is read-only twice over:
# every transaction is read-only (database.yml, and the api_reader role in
# production), and these models refuse to save.
#
# A row is one version, current in release N when release_from <= N and
# (release_to IS NULL OR release_to > N). Query it through FactFactory::Queries,
# which the REST controllers and the MCP server share.
class FactFactoryRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :fact_factory_api, reading: :fact_factory_api }

  # SQL for "this version is current in release :n" on a table alias.
  def self.in_release(table_alias = nil, param: "n")
    prefix = table_alias ? "#{table_alias}." : ""
    "#{prefix}release_from <= :#{param} AND (#{prefix}release_to IS NULL OR #{prefix}release_to > :#{param})"
  end

  def readonly? = true
end
