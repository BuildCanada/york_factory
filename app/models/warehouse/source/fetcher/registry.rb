class Warehouse::Source::Fetcher::Registry
  SPECIALIZED_FORMATS = {
    "worldbank_json" => ->(source) { Warehouse::Source::Fetcher::WorldBankDownload.new(source.url) },
    "statcan_json" => ->(source) { Warehouse::Source::Fetcher::StatcanVectors.new(source.url) },
    "toronto_candidates_json" => lambda { |source|
      Warehouse::Source::Fetcher::TorontoCandidateList.new(source.url, year: election_year(source))
    },
    "brampton_candidates_html" => lambda { |source|
      Warehouse::Source::Fetcher::BramptonCandidateList.new(source.url, year: election_year(source))
    },
    "hamilton_candidates_html" => lambda { |source|
      Warehouse::Source::Fetcher::HamiltonCandidateList.new(source.url, year: election_year(source))
    },
    "spending_transfer_payments_csv" => ->(source) { Warehouse::Source::Fetcher::TransferPayments.new(source.url) },
    "spending_nserc_csv" => ->(source) { Warehouse::Source::Fetcher::NsercAwards.new(source.url) },
    "spending_sshrc_csv" => ->(source) { Warehouse::Source::Fetcher::SshrcAwards.new(source.url) },
    "spending_global_affairs_iati" => ->(source) { Warehouse::Source::Fetcher::GlobalAffairsProjects.new(source.url) },
    "spending_cihr_json" => ->(source) { Warehouse::Source::Fetcher::CihrAwards.new(source.url) }
  }.freeze

  STREAMING_SPENDING_FORMATS = %w[
    spending_proactive_contracts_csv
    spending_aggregated_contracts_csv
    spending_proactive_grants_csv
  ].freeze

  FILE_LOADERS = [
    [ /^infobase/, ->(ingestion, body) { ingestion.infobase_loader.load(csv_content: body) } ],
    [ /^estimates/, ->(ingestion, body) { ingestion.estimates_normalizer.normalize(csv_content: body) } ],
    [ /^lobbying/, ->(ingestion, body) { ingestion.lobbying_normalizer.normalize(csv_content: body) } ],
    [ /\A(?:statcan_boundary|elections_canada|ped_|ward_|sbw_)/,
      ->(ingestion, body) { ingestion.boundary_loader.load(file_content: body) } ],
    [ /^statcan_geo_relationship/, ->(ingestion, body) { ingestion.relationship_loader.load(csv_content: body) } ],
    [ /^statcan_da_population/, ->(ingestion, body) { ingestion.population_loader.load(csv_content: body) } ],
    [ /^oda_/, ->(ingestion, body) { ingestion.address_loader.load(file_content: body) } ],
    [ /^econ_oecd/, ->(ingestion, body) { ingestion.oecd_sdmx_loader.load(csv_content: body) } ],
    [ /^econ_ircc/, ->(ingestion, body) { ingestion.ircc_admissions_loader.load(csv_content: body) } ],
    [ /^econ_owid/, ->(ingestion, body) { ingestion.owid_econ_loader.load(csv_content: body) } ]
  ].freeze

  def self.for(source)
    factory = SPECIALIZED_FORMATS[source.format]
    return factory.call(source) if factory

    loader = if STREAMING_SPENDING_FORMATS.include?(source.format)
      ->(ingestion, body) { ingestion.spending_loader.load(body:) }
    else
      file_loader(source)
    end

    Warehouse::Source::Fetcher::HttpFile.new(
      source.url,
      streaming: STREAMING_SPENDING_FORMATS.include?(source.format),
      &loader
    )
  end

  def self.file_loader(source)
    FILE_LOADERS.find { |pattern, _loader| pattern.match?(source.name) }&.last ||
      lambda do |_ingestion, _body|
        Rails.logger.warn "[Fetcher] No loader configured for source: #{source.name}"
      end
  end

  def self.election_year(source)
    source.name[/(\d{4})\z/, 1]
  end

  private_class_method :file_loader, :election_year
end
