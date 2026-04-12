class Warehouse::LobbyingActivity < Warehouse::Record
  belongs_to :lobbyist
  belongs_to :organization, optional: true
  belongs_to :raw_ingestion, optional: true
  belongs_to :lineage_entry, optional: true
end
