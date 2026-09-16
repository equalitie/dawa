module Auth
  module WebTokenHelper
    #
    # for when we want to create our own web tokens for use with
    # token authentication. this is an alternative to cookie authentication.
    #
    def web_token
      Auth::WebToken.encode(
        { Auth::TokenAuthentication::IDENTITY_KEY => jwt_identity },
        encrypt: true
      )
    end

    def jwt_identity
      cookies[Conf.session_key]
    end
  end
end
