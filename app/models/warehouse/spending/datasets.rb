module Warehouse::Spending::Datasets
  BY_SOURCE = {
    "spending_proactive_contracts" => "contracts-over-10k",
    "spending_aggregated_contracts" => "aggregated-contracts-under-10k",
    "spending_proactive_grants" => "proactive-grants",
    "spending_transfer_payments" => "transfers",
    "spending_global_affairs_projects" => "global_affairs_grants",
    "spending_cihr_awards" => "cihr_grants",
    "spending_nserc_awards" => "nserc_grants",
    "spending_sshrc_awards" => "sshrc_grants"
  }.freeze
  BY_SLUG = BY_SOURCE.invert.freeze

  module_function

  def slug_for(source_name)
    BY_SOURCE.fetch(source_name.to_s)
  end

  def source_name_for(slug)
    BY_SLUG.fetch(slug.to_s)
  end
end
