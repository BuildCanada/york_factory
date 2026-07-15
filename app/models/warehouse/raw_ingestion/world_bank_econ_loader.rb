# Loads World Bank WDI indicator payloads (normalized by
# Source::Fetcher::WorldBankDownload to a flat JSON array) into the economy
# dashboard measures via Warehouse::Economy::ObservationWriter.
class Warehouse::RawIngestion::WorldBankEconLoader < ActiveRecord::AssociatedObject
  performs :load

  # World Bank indicator id -> canonical measure slug
  # (db/seeds/kpis/economy_measures.yml and welfare_measures.yml)
  INDICATORS = {
    "NY.GDP.PCAP.PP.KD" => "gdp-per-capita-ppp",
    "NY.GDP.MKTP.KD.ZG" => "gdp-growth-annual",
    "NE.RSB.GNFS.ZS" => "trade-balance-pct-gdp",
    "FP.CPI.TOTL.ZG" => "inflation-cpi-annual",
    "SL.EMP.TOTL.SP.ZS" => "employment-rate",
    "SP.POP.DPND" => "age-dependency-ratio",
    "SI.POV.GINI" => "gini-index",
    "SI.DST.FRST.20" => "bottom-quintile-income-share",
    "SP.DYN.TFRT.IN" => "fertility-rate",
    "NE.GDI.FTOT.ZS" => "capital-formation-pct-gdp",
    "GOV_WGI_GE.EST" => "government-effectiveness",
    "GB.XPD.RSDV.GD.ZS" => "rd-spending-pct-gdp",
    "NV.IND.MANF.ZS" => "manufacturing-value-added-pct-gdp",
    "IT.NET.BBND.P2" => "fixed-broadband-subscriptions",
    "IS.RRS.GOOD.MT.K6" => "rail-freight-tonne-km",
    "EN.ATM.PM25.MC.M3" => "air-pollution-pm25",
    "ER.LND.PTLD.ZS" => "protected-areas-pct",
    "AG.LND.FRST.ZS" => "forest-area-pct"
  }.freeze

  def load(json_content:)
    rows = JSON.parse(json_content)

    tuples = rows.filter_map do |row|
      measure_slug = INDICATORS[row.dig("indicator", "id")]
      next if measure_slug.nil? || row["value"].nil?

      {
        measure_slug: measure_slug,
        country_code: row["countryiso3code"],
        year: row["date"],
        value: row["value"]
      }
    end

    counts = Warehouse::Economy::ObservationWriter.new(raw_ingestion: raw_ingestion).write(tuples)

    raw_ingestion.update!(status: "complete")
    Rails.logger.info "[WorldBankEconLoader] #{raw_ingestion.source.name}: #{counts.inspect}"
    counts
  rescue => e
    raw_ingestion.update!(status: "failed", error_message: e.message)
    raise
  end
end
