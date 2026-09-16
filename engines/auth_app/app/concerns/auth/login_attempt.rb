module Auth
  module LoginAttempt
    extend ActiveSupport::Concern

    def login_attempt(state, user, credential)
      browser = Browser.new(request.headers["User-Agent"])
      if state == :success
        attempt = nil
        if defined?(Raft::Encryption)
          encryption_context(current_user.userspace) do
            attempt = log_success(user, credential, browser)
          end
        else
          attempt = log_success(user, credential, browser)
        end
        session[:attempt_id] = attempt&.id
      elsif state == :failure
        log_failure(user, credential, browser)
      else
        raise ArgumentError
      end
    end

    private

    def log_success(user, credential, browser)
      Auth::Attempt.create(
        is_success: true,
        user: user,
        credential: credential,
        encrypted_data: {
          browser: browser.name,
          version: browser.full_version,
          platform: browser.platform.name
        }
      )
    end

    def log_failure(user, credential, browser)
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
    end
  end
end
