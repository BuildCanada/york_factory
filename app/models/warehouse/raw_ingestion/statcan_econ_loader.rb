# Loads Statistics Canada WDS vector payloads (normalized by
# Source::Fetcher::StatcanVectors to a flat JSON array) into dashboard
# measures via Warehouse::Economy::ObservationWriter. All StatCan vectors are
# Canada-only; the writer keys each row annually or monthly based on the
# measure's frequency (refPer is passed through as the period).
class Warehouse::RawIngestion::StatcanEconLoader < ActiveRecord::AssociatedObject
  performs :load

  # StatCan vector id -> canonical measure slug
  # (db/seeds/kpis/welfare_measures.yml, housing_measures.yml and
  # economy_measures.yml)
  VECTORS = {
    96439638 => "gini-after-tax-canada",
    96730402 => "low-income-entry-rate",
    96730403 => "low-income-exit-rate",
    730579 => "housing-starts-canada",
    733334 => "rental-vacancy-rate-canada",
    44312461 => "crime-severity-index",
    44407600 => "police-reported-crime-rate",
    # Table 36-10-0434: real GDP at basic prices, all industries, Canada,
    # monthly, seasonally adjusted at annual rates, chained 2017 $ millions
    65201210 => "gdp-monthly-canada",
    # Table 36-10-0706: real GDP per capita, quarterly, chained 2017 dollars
    1645315579 => "gdp-per-capita-canada",
    # Table 18-10-0004: CPI monthly, not seasonally adjusted, Canada, 2002=100
    41690973 => "cpi-all-items",
    41690974 => "cpi-food",
    41691050 => "cpi-shelter",
    41691052 => "cpi-rent",
    41691108 => "cpi-clothing-footwear",
    41691128 => "cpi-transportation",
    41691136 => "cpi-gasoline",
    41691239 => "cpi-energy",
    # Table 14-10-0287: LFS employment rate by age group, monthly, SA, percent
    2062817 => "employment-rate-15-plus",
    2062844 => "employment-rate-15-to-24",
    2062952 => "employment-rate-25-to-54",
    101885408 => "employment-rate-55-to-64",
    # Table 14-10-0287: LFS unemployment rate by age group, monthly, SA, percent
    2062815 => "unemployment-rate-15-plus",
    2062842 => "unemployment-rate-15-to-24",
    2062950 => "unemployment-rate-25-to-54",
    101885216 => "unemployment-rate-55-to-64",
    # Table 14-10-0288: employment by class of worker, monthly, SA, thousands
    2066967 => "employment-all-classes",
    2066969 => "employment-public-sector",
    2066970 => "employment-private-sector",
    2066971 => "employment-self-employed",
    # Table 33-10-0270: business dynamics, monthly, SA, counts (entrants =
    # first-ever appearance; exits = permanent disappearance, ~6-month lag)
    1203704156 => "active-businesses",
    1271259491 => "business-entrants",
    1203704157 => "business-openings",
    1296954897 => "business-exits",
    # Table 33-10-0165: discontinued quarterly business entry/exit, 2000-2019.
    # Entrants, private sector (broad entry concept, matches business-openings).
    114829668 => "business-entries-historical",
    # Table 36-10-0025: FDI flows, quarterly, CAD millions
    61913923 => "fdi-inflows",
    61913911 => "fdi-outflows",
    # Table 36-10-0008: international investment position, annual, CAD millions
    # (book-value stock, all countries). Inward = FDI in Canada; outward = CDIA.
    7117859 => "fdi-position-in-canada",
    7117682 => "cdi-position-abroad",
    # Table 36-10-0104: GDP expenditure-based, quarterly, chained 2017 $M SAAR
    62305732 => "gross-fixed-capital-formation",
    62305733 => "business-gross-fixed-capital-formation",
    # Table 38-10-0237: general government debt ratios, quarterly, % of GDP
    62698056 => "govt-gross-debt-to-gdp",
    62698059 => "govt-net-debt-to-gdp",
    # Table 11-10-0065: household debt service indicators, quarterly, seasonally
    # adjusted. Mortgage debt service ratio — obligated mortgage principal and
    # interest payments as a percent of household disposable income.
    1001696814 => "mortgage-debt-service-ratio",
    # Table 14-10-0064: employee hourly wages, annual, current dollars
    2196615 => "average-hourly-wage",
    2196617 => "median-hourly-wage",
    # Table 17-10-0009: population estimates, quarterly, persons (Canada total)
    1 => "population-canada",
    # Table 17-10-0008: components of demographic growth, annual (Jul-Jun)
    391099 => "immigrants-annual",
    29768526 => "emigrants-annual",
    29768527 => "returning-emigrants-annual",
    29768529 => "net-non-permanent-residents-annual",
    # Table 17-10-0121: non-permanent residents by type, quarterly stock
    1566927590 => "npr-total",
    1566927591 => "npr-asylum-claimants",
    1566927597 => "npr-work-permit-holders",
    1566927598 => "npr-study-permit-holders",
    1566927599 => "npr-work-and-study-permit-holders"
  }.freeze

  # Table 33-10-0087 (LEAP annual business dynamics) has no Canada geography
  # member — only the ten provinces and the territories. The national
  # "business-entrants-annual" total is summed from these eleven provincial
  # "Number of entrants; Private sector" vectors per year (see the summing
  # branch in #load). Kept out of VECTORS so they don't each become a measure.
  LEAP_ENTRANT_VECTORS = [
    90465270,  # Newfoundland and Labrador
    90465378,  # Prince Edward Island
    90465486,  # Nova Scotia
    90465594,  # New Brunswick
    90465702,  # Quebec
    90465810,  # Ontario
    90465918,  # Manitoba
    90466026,  # Saskatchewan
    90466134,  # Alberta
    90466242,  # British Columbia
    90466350   # Territories
  ].freeze

  # Net debt excluding CPP/QPP, computed per quarter (see
  # #net_debt_excl_pension_tuples). StatCan's ready-made net-debt ratio
  # (38-10-0237) nets out the pension plans' large asset holdings, which masks
  # how much the government actually owes; this measure adds those assets back.
  # Table 10-10-0015-01 net financial worth, $M: consolidated government and
  # CPP/QPP. Table 36-10-0104 nominal GDP at market prices (current $, seasonally
  # adjusted at annual rates), $M — the denominator. Kept out of VECTORS so the
  # raw inputs don't each become a measure.
  NFW_CONSOLIDATED_VECTOR = 52531052
  NFW_CPP_QPP_VECTOR = 52531280
  NOMINAL_GDP_VECTOR = 62305783

  def load(json_content:)
    rows = JSON.parse(json_content)

    tuples = rows.filter_map do |row|
      measure_slug = VECTORS[row["vectorId"]]
      next if measure_slug.nil? || row["value"].nil?

      {
        measure_slug: measure_slug,
        country_code: "CAN",
        year: row.fetch("refPer").to_s.first(4),
        period: row.fetch("refPer"),
        value: row["value"]
      }
    end

    tuples.concat(leap_entrant_tuples(rows))
    tuples.concat(net_debt_excl_pension_tuples(rows))

    counts = Warehouse::Economy::ObservationWriter.new(raw_ingestion: raw_ingestion).write(tuples)

    raw_ingestion.update!(status: "complete")
    Rails.logger.info "[StatcanEconLoader] #{raw_ingestion.source.name}: #{counts.inspect}"
    counts
  rescue => e
    raw_ingestion.update!(status: "failed", error_message: e.message)
    raise
  end

  private

  # Sums the eleven provincial/territorial LEAP entrant vectors into one
  # national "business-entrants-annual" tuple per year. Only years where all
  # eleven jurisdictions report are emitted, so a partial year never shows as
  # an artificial dip. Returns [] for any ingestion that carries none of these
  # vectors (i.e. every source other than the LEAP one).
  def leap_entrant_tuples(rows)
    leap = rows.select { |r| LEAP_ENTRANT_VECTORS.include?(r["vectorId"]) && !r["value"].nil? }
    return [] if leap.empty?

    leap.group_by { |r| r.fetch("refPer").to_s.first(4) }.filter_map do |year, year_rows|
      next unless year_rows.map { |r| r["vectorId"] }.uniq.size == LEAP_ENTRANT_VECTORS.size

      {
        measure_slug: "business-entrants-annual",
        country_code: "CAN",
        year: year,
        period: year_rows.first.fetch("refPer"),
        value: year_rows.sum { |r| r["value"] }
      }
    end
  end

  # Computes general government net debt EXCLUDING CPP/QPP assets as a share of
  # GDP, per quarter. Net financial worth (financial assets minus liabilities)
  # for the consolidated government already nets out CPP/QPP holdings; adding
  # those back — subtracting the pension plans' net financial worth — isolates
  # the government's own financial position. Net debt is the negative of that
  # net financial worth, divided by nominal GDP and expressed as a percent.
  # All three vectors are quarterly $M and share a refPer. Returns [] for any
  # ingestion missing these vectors (i.e. every source but the net-debt one).
  def net_debt_excl_pension_tuples(rows)
    wanted = [ NFW_CONSOLIDATED_VECTOR, NFW_CPP_QPP_VECTOR, NOMINAL_GDP_VECTOR ]
    relevant = rows.select { |r| wanted.include?(r["vectorId"]) && !r["value"].nil? }
    return [] if relevant.empty?

    relevant.group_by { |r| r.fetch("refPer") }.filter_map do |ref_per, period_rows|
      by_vector = period_rows.index_by { |r| r["vectorId"] }
      consolidated = by_vector[NFW_CONSOLIDATED_VECTOR]
      cpp_qpp = by_vector[NFW_CPP_QPP_VECTOR]
      gdp = by_vector[NOMINAL_GDP_VECTOR]
      next if consolidated.nil? || cpp_qpp.nil? || gdp.nil? || gdp["value"].zero?

      net_financial_worth = consolidated["value"] - cpp_qpp["value"]
      {
        measure_slug: "govt-net-debt-excl-pension-to-gdp",
        country_code: "CAN",
        year: ref_per.to_s.first(4),
        period: ref_per,
        value: -net_financial_worth / gdp["value"] * 100.0
      }
    end
  end
end
