module Internal
  # The edge Worker's key lookup (the WS-H contract,
  # docs/public-interface-design.md §14 WS-E):
  #
  #   GET /internal/keys/lookup?digest=<hex HMAC-SHA256(API_KEY_PEPPER, key)>
  #
  # signed with Edge::Signature. Answers ApiKey#lookup_payload for any key the
  # digest names, including revoked and expired ones (so the Worker can cache
  # the refusal), and 404 for an unknown digest. The Worker never sends the
  # key itself.
  class KeysController < ActionController::API
    before_action :verify_signature!

    def lookup
      digest = params[:digest].to_s
      return render(json: { error: "invalid_digest" }, status: :bad_request) unless digest.match?(/\A\h{64}\z/)

      api_key = ApiKey.includes(:account).find_by(token_digest: digest)
      return render(json: { error: "not_found" }, status: :not_found) unless api_key

      response.headers["Cache-Control"] = "no-store"
      render json: api_key.lookup_payload
    end

    private

    def verify_signature!
      valid = Edge::Signature.valid?(
        method: request.request_method,
        path: request.fullpath,
        body: request.raw_post.to_s,
        timestamp: request.headers[Edge::Signature::TIMESTAMP_HEADER],
        signature: request.headers[Edge::Signature::SIGNATURE_HEADER]
      )
      render json: { error: "invalid_signature" }, status: :unauthorized unless valid
    end
  end
end
