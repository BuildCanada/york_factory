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

    counts = Warehouse::Economy::ObservationWriter.new(raw_ingestion: raw_ingestion).write(tuples)

    raw_ingestion.update!(status: "complete")
    Rails.logger.info "[StatcanEconLoader] #{raw_ingestion.source.name}: #{counts.inspect}"
    counts
  rescue => e
    raw_ingestion.update!(status: "failed", error_message: e.message)
    raise
  end
end
