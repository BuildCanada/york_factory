# Ensure CREATE EXTENSION lines for extensions whose objects aren't directly
# referenced via TYPE relationships (pg_trgm operator classes, unaccent functions)
# survive `bin/rails db:schema:dump` for the primary database. Without explicit
# --extension flags, pg_dump emits postgis (tables reference geometry types) but
# silently drops pg_trgm and unaccent under the schema-filter invocation Rails uses.
#
# Wrapping ActiveRecord::Tasks::PostgreSQLDatabaseTasks#structure_dump so the
# flags apply only to the primary DB (queue/cache/cable don't have these extensions).
Rails.application.config.after_initialize do
  require "active_record/tasks/postgresql_database_tasks"

  module StructureDumpExtensions
    PRIMARY_EXTENSIONS = %w[postgis pg_trgm unaccent].freeze

    def structure_dump(filename, extra_flags)
      if @configuration_hash.dig(:database).to_s.match?(/_(queue|cache|cable)\z/) || filename.to_s.match?(/(queue|cache|cable)_structure\.sql\z/)
        return super
      end

      added = PRIMARY_EXTENSIONS.map { |e| "--extension=#{e}" }
      super(filename, Array(extra_flags) + added)
    end
  end
  ActiveRecord::Tasks::PostgreSQLDatabaseTasks.prepend(StructureDumpExtensions)
end
