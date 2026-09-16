module Auth
  module LoginAttempt
    extend ActiveSupport::Concern

    def login_attempt(state, user, credential)
      browser = Browser.new(request.headers["User-Agent"])
      if state == :success
        encryption_context(current_user.userspace) do
          attempt = Auth::Attempt.create(
            is_success: true,
            user: user,
            credential: credential,
            encrypted_data: {
              browser: browser.name,
              version: browser.full_version,
              platform: browser.platform.name
            }
          )
          session[:attempt_id] = attempt&.id
        end
      elsif state == :failure
        Auth::Attempt.create(
          is_success: false,
          user: user,
          credential: credential,
          cleartext_data: {
            browser: browser.name,
            version: browser.full_version,
            platform: browser.platform.name
          }
        )
      else
        raise ArgumentError
      end
    end

  end
end
