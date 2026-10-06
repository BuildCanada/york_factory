module Oauth
  # Public-API behaviour for Doorkeeper::AccessGrant (included from
  # config/initializers/doorkeeper.rb): the resource and account chosen at
  # consent, copied to the token when the code is redeemed.
  module AccessGrantExtension
    extend ActiveSupport::Concern

    included do
      belongs_to :account, optional: true
    end
  end
end
