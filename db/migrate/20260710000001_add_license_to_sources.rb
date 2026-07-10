class AddLicenseToSources < ActiveRecord::Migration[8.1]
  # Economy dashboard sources redistribute third-party data (OWID grapher
  # CSVs are CC BY 4.0 and require attribution; StatCan/World Bank/OECD have
  # their own open licenses). Track each source's license and the attribution
  # line dashboards must display alongside the data.
  def change
    add_column "warehouse.sources", :license, :string
    add_column "warehouse.sources", :attribution, :string
  end
end
