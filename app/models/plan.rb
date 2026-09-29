# The public API plans of docs/public-interface-design.md §6.2, as code.
# Starting numbers, to be retuned after 30 days of use. WS-I (usage and
# quotas) builds on this; WS-E needs it for key limits and the edge lookup.
class Plan
  Definition = Data.define(:name, :rate, :burst, :monthly, :daily, :key_limit, :persons) do
    def label = name.titleize

    # The `limits` object of the edge key lookup contract. nil means unlimited.
    def limits = { rate:, burst:, monthly:, daily: }.compact
  end

  ALL = {
    "anonymous" => Definition.new(name: "anonymous", rate: 30, burst: 30, monthly: nil, daily: 1_000, key_limit: 0, persons: false),
    "free" => Definition.new(name: "free", rate: 120, burst: 240, monthly: 100_000, daily: nil, key_limit: 5, persons: true),
    "internal" => Definition.new(name: "internal", rate: 1_200, burst: 2_400, monthly: nil, daily: nil, key_limit: 50, persons: true),
    "partner" => Definition.new(name: "partner", rate: 600, burst: 1_200, monthly: 2_000_000, daily: nil, key_limit: 20, persons: true),
    "paid" => Definition.new(name: "paid", rate: 600, burst: 1_200, monthly: 1_000_000, daily: nil, key_limit: 20, persons: true)
  }.freeze

  NAMES = ALL.keys.freeze

  def self.fetch(name) = ALL.fetch(name.to_s)
end
