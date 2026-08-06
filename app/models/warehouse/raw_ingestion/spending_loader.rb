class Warehouse::RawIngestion::SpendingLoader < ActiveRecord::AssociatedObject
  performs :load

  SCRAPERS = {
    "spending_proactive_contracts" => "Warehouse::Spending::Scrapers::ProactiveContracts",
    "spending_aggregated_contracts" => "Warehouse::Spending::Scrapers::AggregatedContracts",
    "spending_proactive_grants" => "Warehouse::Spending::Scrapers::ProactiveGrants",
    "spending_transfer_payments" => "Warehouse::Spending::Scrapers::TransferPayments",
    "spending_global_affairs_projects" => "Warehouse::Spending::Scrapers::GlobalAffairsProjects",
    "spending_nserc_awards" => "Warehouse::Spending::Scrapers::NsercAwards",
    "spending_cihr_awards" => "Warehouse::Spending::Scrapers::CihrAwards",
    "spending_sshrc_awards" => "Warehouse::Spending::Scrapers::SshrcAwards"
  }.freeze

  def load(body:, withdraw_missing: true, withdrawal_scope: nil)
    scraper_class.new(raw_ingestion).load(
      body,
      withdraw_missing: withdraw_missing,
      withdrawal_scope: withdrawal_scope
    )
  end

  private

  def scraper_class
    SCRAPERS.fetch(raw_ingestion.source.name).constantize
  rescue KeyError
    raise ArgumentError, "No spending scraper configured for #{raw_ingestion.source.name.inspect}"
  end
end
