# Spending datasets and award-search collectors ported from the legacy
# Canada Spends scraper. URLs point at first-party Government of Canada data.
sources = [
  {
    name: "spending_proactive_contracts",
    url: "https://open.canada.ca/data/en/datastore/dump/fac950c0-00d5-4ec1-a4d3-9cbebf98a305?bom=True",
    format: "spending_proactive_contracts_csv",
    frequency: "weekly",
    attribution: "Government of Canada Proactive Disclosure — Contracts"
  },
  {
    name: "spending_aggregated_contracts",
    url: "https://open.canada.ca/data/en/datastore/dump/2e9a82e2-bb18-4bff-a61e-59af3b429672?bom=True",
    format: "spending_aggregated_contracts_csv",
    frequency: "quarterly",
    attribution: "Government of Canada Proactive Disclosure — Aggregated Contracts under $10,000"
  },
  {
    name: "spending_proactive_grants",
    url: "https://open.canada.ca/data/dataset/432527ab-7aac-45b5-81d6-7597107a7013/resource/1d15a62f-5656-49ad-8c88-f40ce689d831/download/grants.csv",
    format: "spending_proactive_grants_csv",
    frequency: "weekly",
    attribution: "Government of Canada Proactive Disclosure — Grants and Contributions"
  },
  {
    name: "spending_transfer_payments",
    url: "https://open.canada.ca/data/api/action/package_show?id=69bdc3eb-e919-4854-bc52-a435a3e19092",
    format: "spending_transfer_payments_csv",
    frequency: "annual",
    attribution: "Public Accounts of Canada — Yearly Transfer Payments"
  },
  {
    name: "spending_global_affairs_projects",
    url: "https://www.international.gc.ca/world-monde/issues_development-enjeux_developpement/priorities-priorites/initiative.aspx?lang=eng",
    format: "spending_global_affairs_iati",
    frequency: "daily",
    attribution: "Global Affairs Canada IATI Activity Files"
  },
  {
    name: "spending_cihr_awards",
    url: "https://webapps.cihr-irsc.gc.ca/decisions/sq",
    format: "spending_cihr_json",
    frequency: "monthly",
    attribution: "Canadian Institutes of Health Research Funding Decisions Database"
  },
  {
    name: "spending_nserc_awards",
    url: "https://open.canada.ca/data/api/action/package_show?id=c1b0f627-8c29-427c-ab73-33968ad9176e",
    format: "spending_nserc_csv",
    frequency: "monthly",
    attribution: "NSERC Awards Database"
  },
  {
    name: "spending_sshrc_awards",
    url: "https://open.canada.ca/data/api/action/package_show?id=b4e2b302-9bc6-4b33-b880-6496f8cef0f1",
    format: "spending_sshrc_csv",
    frequency: "monthly",
    attribution: "SSHRC Awards Database"
  }
]

sources.each do |attributes|
  source = Warehouse::Source.find_or_initialize_by(name: attributes.fetch(:name))
  source.assign_attributes(
    url: attributes.fetch(:url),
    format: attributes.fetch(:format),
    fetch_frequency: attributes.fetch(:frequency),
    license: "Open Government Licence — Canada",
    attribution: attributes.fetch(:attribution)
  )
  source.save!
end
