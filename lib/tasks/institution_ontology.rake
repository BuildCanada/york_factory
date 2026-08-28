namespace :institution_ontology do
  desc "Import a validated Nova Scotia municipality release manifest"
  task :import_ns_municipalities, [ :version, :input_path ] => :environment do |_task, args|
    version = args[:version].presence || abort("version is required")
    input_path = args[:input_path].presence || abort("input_path is required")

    release = Warehouse::InstitutionRelease::NovaScotiaMunicipalityImporter.new(
      path: input_path,
      version: version
    ).import!

    puts "Imported #{release.institutions.where.not(canonical_id: 'ca/ns').count} municipalities into release #{release.version}"
  end

  desc "Import one dated release from semicolon-separated jurisdiction institution manifests"
  task :import_municipalities, [ :version, :input_paths ] => :environment do |_task, args|
    version = args[:version].presence || abort("version is required")
    input_paths = args[:input_paths].to_s.split(";").map(&:strip).reject(&:empty?)
    abort("at least one input manifest is required") if input_paths.empty?

    release = Warehouse::InstitutionRelease::CombinedMunicipalityImporter.new(
      paths: input_paths,
      version: version
    ).import!

    province_ids = input_paths.map { |path| JSON.parse(File.read(path)).fetch("province").fetch("code") }
    local_count = release.institutions.where.not(government_level: %w[provincial territorial]).count
    puts "Imported #{local_count} institutions for #{province_ids.join(', ')} into release #{release.version}"
  end

  desc "Atomically import jurisdiction manifests and a First Nations manifest into one dated release"
  task :import_national, [
    :version, :input_paths, :first_nations_path, :first_nations_assets_path,
    :csd_inventory_path, :csd_authority_paths
  ] => :environment do |_task, args|
    version = args[:version].presence || abort("version is required")
    input_paths = args[:input_paths].to_s.split(";").map(&:strip).reject(&:empty?)
    first_nations_path = args[:first_nations_path].presence || abort("first_nations_path is required")
    csd_inventory_path = args[:csd_inventory_path].presence || abort("csd_inventory_path is required")
    csd_authority_paths = args[:csd_authority_paths].to_s.split(";").map(&:strip).reject(&:empty?)
    abort("at least one jurisdiction manifest is required") if input_paths.empty?

    release = Warehouse::Record.transaction do
      imported_release = Warehouse::InstitutionRelease::CombinedMunicipalityImporter.new(
        paths: input_paths,
        version: version
      ).import!
      Warehouse::InstitutionRelease::FirstNations::ManifestImporter.new(
        release: imported_release,
        path: first_nations_path,
        asset_inventory_path: args[:first_nations_assets_path].presence
      ).import!
      Warehouse::InstitutionRelease::CsdAuthorityImporter.new(
        release: imported_release,
        inventory_path: csd_inventory_path,
        authority_paths: csd_authority_paths
      ).import!
      imported_release.validate_complete!
      imported_release
    end

    counts = release.institutions.group(:government_level).count.sort.to_h
    puts "Imported national release #{release.version}: #{release.institutions.count} institutions, " \
      "#{release.institution_documents.count} documents, #{release.institution_document_assets.count} assets"
    puts "Government levels: #{counts.map { |level, count| "#{level}=#{count}" }.join(', ')}"
  end

  desc "Export an immutable institution ontology release to Parquet"
  task :export, [ :version, :output_directory ] => :environment do |_task, args|
    version = args[:version].presence || abort("version is required")
    release = Warehouse::InstitutionRelease.find_by!(version: version)
    output = args[:output_directory].presence ||
      Rails.root.join("tmp", "public-institutions-#{release.version}")

    directory = Warehouse::InstitutionRelease::Exporter.new(
      release,
      output_directory: output
    ).export!

    puts "Exported #{release.version} to #{directory}"
  end
end
