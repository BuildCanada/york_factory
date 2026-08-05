namespace :search do
  desc "Backfill every source-owned searchable record"
  task backfill: :environment do
    Searchable.models.each do |model|
      scope = model.respond_to?(:search_indexable) ? model.search_indexable : model.all
      scope.find_each do |record|
        record.sync_to_search!
      end
    end
  end

  desc "Remove obsolete per-observation and KPI-document rows from Turbopuffer"
  task remove_legacy_kpi_rows: :environment do
    namespace = Search.turbopuffer_namespace
    ids = Warehouse::CanonicalObservation.ids.map { |id| "canonical_observation:#{id}" }
    ids.concat(Warehouse::KpiDocument.ids.map { |id| "kpi_document:#{id}" })
    ids.each_slice(1_000) do |batch|
      namespace.write(deletes: batch, return_affected_ids: true)
    end
    puts "Removed #{ids.length} legacy KPI search rows"
  end
end
