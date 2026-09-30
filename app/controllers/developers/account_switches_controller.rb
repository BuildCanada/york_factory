module Developers
  class AccountSwitchesController < BaseController
    def create
      account = current_user.accounts.find(params.require(:account_id))
      session[:developer_account_id] = account.id
      redirect_to developers_path, notice: "Switched to #{account.name}."
    end
  end
end
