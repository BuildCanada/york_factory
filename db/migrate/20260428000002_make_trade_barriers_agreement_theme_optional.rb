class MakeTradeBarriersAgreementThemeOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :trade_barriers_agreements, :theme_id, true
  end
end
