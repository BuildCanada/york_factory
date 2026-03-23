class LobbyingActivity < ApplicationRecord
  belongs_to :lobbyist
  belongs_to :government_entity, optional: true
  belongs_to :raw_ingestion, optional: true
  belongs_to :lineage_entry, optional: true
end
