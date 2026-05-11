module Api
  module V1
    module Auth
      class LinkedinController < ActionController::Base
        # The popup runs LinkedIn's OAuth dance and posts a verified ticket back
        # to the configured frontend origin. CSRF doesn't apply (the OAuth
        # redirect is a GET initiated by LinkedIn).
        protect_from_forgery with: :null_session
        layout false

        STATE_TTL = 15.minutes

        def start
          kind = params[:kind].to_s
          memo_slug = params[:memo_slug].to_s
          return render plain: "invalid kind", status: :bad_request unless VerificationTicket::ALLOWED_KINDS.include?(kind)
          return render plain: "memo_slug required", status: :bad_request if memo_slug.blank?

          nonce = SecureRandom.hex(16)
          state = state_jwt(kind: kind, memo_slug: memo_slug, nonce: nonce)
          redirect_to LinkedinOidc.authorize_url(state: state, nonce: nonce), allow_other_host: true
        end

        def callback
          if params[:error].present?
            return render_callback_html(error: params[:error_description].presence || params[:error])
          end
          state_payload = decode_state(params[:state])
          tokens = LinkedinOidc.exchange_code(params[:code])
          identity = LinkedinOidc.verify_id_token(tokens["id_token"], nonce: state_payload["nonce"])

          ticket = VerificationTicket.issue(identity, kind: state_payload["kind"], memo_slug: state_payload["memo_slug"])
          payload = identity.slice(*VerificationTicket::IDENTITY_FIELDS)

          @verified_ticket = ticket
          @payload_json    = payload.to_json
          @origin          = LinkedinOidc.postmessage_origin
          render :callback
        rescue VerificationTicket::Error, LinkedinOidc::Error, JWT::DecodeError, KeyError => e
          render_callback_html(error: e.message)
        end

        private

        def state_jwt(kind:, memo_slug:, nonce:)
          now = Time.current.to_i
          JWT.encode(
            { "kind" => kind, "memo_slug" => memo_slug, "nonce" => nonce, "iat" => now, "exp" => now + STATE_TTL.to_i },
            VerificationTicket.secret,
            "HS256"
          )
        end

        def decode_state(token)
          payload, _ = JWT.decode(token.to_s, VerificationTicket.secret, true, algorithm: "HS256", verify_iat: true)
          payload
        end

        def render_callback_html(error:)
          @error = error
          @origin = (LinkedinOidc.postmessage_origin rescue "*")
          render :callback, status: :ok
        end
      end
    end
  end
end
