require "digest"

class Warehouse::FinancialStatementExtraction::CandidateSet
  DEFAULT_ASSET_ROOT = Pathname("/Volumes/floppy/york_factory/public_institutions/assets")
  PROVINCES = %w[ab bc mb nb nl ns nt nu on pe qc sk yt].freeze

  Candidate = Data.define(
    :document_id, :institution_canonical_id, :institution_name,
    :document_canonical_id, :asset_sha256, :fiscal_year_end,
    :pdf_path, :population
  )

  attr_reader :release, :provinces, :years, :institution_ids, :asset_root

  def initialize(release:, provinces: nil, years: nil, institution_ids: nil,
    asset_root: ENV.fetch("PUBLIC_INSTITUTION_ASSET_ROOT", DEFAULT_ASSET_ROOT.to_s))
    @release = release
    @provinces = Array(provinces).presence&.map { normalize_province(_1) }&.uniq
    @years = Array(years).presence&.map { Integer(_1) }&.uniq
    @institution_ids = Array(institution_ids).presence&.map(&:to_s)&.uniq
    @asset_root = Pathname(asset_root).expand_path
    @population_by_institution_id = {}
  end

  def count
    return relation.count unless years

    each.count
  end

  def each(start: nil)
    return enum_for(__method__, start:) unless block_given?

    scope = relation.order(:id)
    scope = scope.where("warehouse.institution_documents.id >= ?", start) if start
    scope.find_each do |document|
      fiscal_year_end = fiscal_year_end_for(document)
      next if years && !fiscal_year_end.year.in?(years)

      asset = document.institution_document_assets.find(&:preferred?)
      yield Candidate.new(
        document_id: document.id,
        institution_canonical_id: document.institution.canonical_id,
        institution_name: document.institution.name_en.presence || document.institution.name_fr,
        document_canonical_id: document.canonical_id,
        asset_sha256: asset.content_sha256,
        fiscal_year_end:,
        pdf_path: safe_asset_path(asset.archive_path),
        population: population_for(document.institution)
      )
    end
  end

  def audit(verify_hashes: false)
    result = { candidates: 0, missing_files: [], size_mismatches: [], hash_mismatches: [] }
    each do |candidate|
      result[:candidates] += 1
      unless candidate.pdf_path.file?
        result[:missing_files] << candidate.document_canonical_id
        next
      end

      asset = release.institution_document_assets.find_by!(
        institution_document_id: candidate.document_id, preferred: true
      )
      if candidate.pdf_path.size != asset.byte_size
        result[:size_mismatches] << candidate.document_canonical_id
      end
      if verify_hashes && Digest::SHA256.file(candidate.pdf_path).hexdigest != candidate.asset_sha256
        result[:hash_mismatches] << candidate.document_canonical_id
      end
    end
    result
  end

  private

  def relation
    scope = release.institution_documents
      .joins(:institution, :institution_document_assets)
      .includes(:institution, :institution_document_assets)
      .where(document_type: "financial-statements")
      .where("warehouse.institution_document_assets" => { preferred: true, mime_type: "application/pdf" })
    if provinces
      patterns = provinces.map { "ca/#{_1}/%" }
      clauses = patterns.map { "warehouse.institutions.canonical_id LIKE ?" }.join(" OR ")
      scope = scope.where(clauses, *patterns)
    end
    scope = scope.where("warehouse.institutions" => { canonical_id: institution_ids }) if institution_ids
    scope
  end

  def fiscal_year_end_for(document)
    return document.fiscal_period_end if document.fiscal_period_end

    match = document.canonical_id.match(%r{/documents/financial-statements/(\d{4})/})
    raise ArgumentError, "document has no fiscal year: #{document.canonical_id}" unless match

    Date.new(Integer(match[1]), 12, 31)
  end

  def safe_asset_path(relative_path)
    path = asset_root.join(relative_path).expand_path
    unless path.to_s.start_with?("#{asset_root}/")
      raise ArgumentError, "asset path escapes root: #{relative_path}"
    end

    path
  end

  def population_for(institution)
    @population_by_institution_id.fetch(institution.id) do
      snapshots = institution.institution_geographies
        .where(role: %w[governs administers])
        .includes(:institution_geography_snapshot)
        .map(&:institution_geography_snapshot)
      profiles = Warehouse::CensusProfile.where(
        census_year: snapshots.map(&:census_year), geo_level: "csd", geo_uid: snapshots.map(&:geo_uid)
      ).index_by { [ _1.census_year, _1.geo_uid ] }
      population = snapshots.sum do |snapshot|
        profiles[[ snapshot.census_year, snapshot.geo_uid ]]&.population.to_i.nonzero? || snapshot.population.to_i
      end
      @population_by_institution_id[institution.id] = population.positive? ? population : nil
    end
  end

  def normalize_province(value)
    province = value.to_s.downcase
    raise ArgumentError, "unsupported province #{value.inspect}" unless province.in?(PROVINCES)

    province
  end
end
