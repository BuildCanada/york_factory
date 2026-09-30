module KeyIssuers
  class LocalIssuer
    SECRET_LENGTH = 40

    def name = "local"

    def issue(_api_key) = Issued.new(secret: SecureRandom.alphanumeric(SECRET_LENGTH), bifrost_vk_id: nil)

    def deactivate(_api_key) = true
  end
end
