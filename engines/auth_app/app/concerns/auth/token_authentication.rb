#
# Some requests rely on a web token (Javascript Web Token format) for
# authentication, instead of a cookie.
#
# The problem: the document editor & blobs controllers need to fetch encrypted
# blobs but without a cookie-based session.
#
# The solution: the Authorization header for these requests contain a JWT
# that contains the cookie's session_id.
#
module Auth
  module TokenAuthentication
    extend ActiveSupport::Concern
    IDENTITY_KEY = "identity_id"

    included do
      prepend_before_action :authenticate_from_token
      helper "auth/web_token"

      #helper_method :web_token
      #helper_method :jwt_identity
    end

    private

    def authenticate_from_token
      return if @current_user
      @web_token = Auth::WebToken.get(request)
      if @web_token.present?
        ids = extract_session_ids_from_token(@web_token)
        ids.each do |public_session_id|
          if load_session_by_id(public_session_id)
            break
          end
        end
      end
    end

    def load_session_by_id(public_session_id)
      session = Auth::SessionSecure.find_by_public_id(public_session_id)
      if session
        @current_vault = Auth::SessionVault.new(session)
        if session.link_id
          @current_link = Link.find_by_id(session.link_id)
          @current_user = Anon::User.new(@current_link,
            display_name: session.data["link_display_name"],
            code: session.data["link_membership_code"]
          )
        elsif session.user_id
          @current_user = User.find_by_id(session.user_id)
        end
      end
    end

    def extract_session_ids_from_token(token)
      if token[IDENTITY_KEY]
        [token[IDENTITY_KEY]]
      elsif defined?(Files::OnlyOfficeToken)
        Files::OnlyOfficeToken.new(token).identifiers
      end
    end
  end
end
