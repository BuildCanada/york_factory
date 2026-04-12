class WarehouseRecord < ActiveRecord::Base
  self.abstract_class = true
  self.table_name_prefix = "warehouse."
end
