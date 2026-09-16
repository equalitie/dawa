require "active_record/session_store"
require "webauthn"
require_relative "auth/engine"

module Auth
  # encryption
  mattr_accessor :key_provider, default: Auth::KeyProvider.new
  mattr_accessor :app_public_key
  mattr_accessor :app_private_key
  mattr_accessor :salt

  # login page
  mattr_accessor :login_url, default: "auth.new_session_url"

  # home when authenticated
  mattr_accessor :home_url, default: "main_app.home_url"

  # home when not authenticated
  mattr_accessor :root_url, default: "main_app.root_url"

  mattr_accessor :preserve_session_keys, default: [ :locale, :timezone ]

  # if true, email is used for login, and login is not required
  # when resetting a password using an email address
  # mattr_accessor :login_is_email, default: false

  # the default domain to use if none is specified.
  # mattr_accessor :default_domain, default: nil

  # array of usernames that cannot be used by normal users
  mattr_accessor :forbidden_usernames, default: %w(
    admin anon contact hello help help-desk info root security security-staff staff support support-staff sysadmin team web-master
  )

  # the from address for outgoing emails
  # mattr_accessor :from_address

  # the authentication services that are enabled
  mattr_accessor :services, default: {
    # webauthn: Service::WebAuthn,
    # recovery_code: Service::RecoveryCode,
    # primary: Service::Primary,
    # recovery_token: Service::RecoveryToken,
    # testing: ((Rails.env.development? || Rails.env.test?) ? Service::Testing : nil)
  }

  # zxcvbn score:
  # 0 =      too guessable: risky password.
  #                         guesses < 10^3
  #
  # 1 =     very guessable: protection from throttled online attacks.
  #                         guesses < 10^6
  #
  # 2 = somewhat guessable: protection from unthrottled online attacks.
  #                         guesses < 10^8
  #
  # 3 = safely unguessable: moderate protection from offline slow-hash scenario
  #                         guesses < 10^10
  #
  # 4 =   very unguessable: strong protection from offline slow-hash scenario
  #                         guesses >= 10^10
  mattr_accessor :minimum_password_strength_score, default: 4

  # Whether to update user#last_login_on  after sucessfuly log in
  mattr_accessor :update_last_login, default: true

  # This allows users to reset their password using their main email
  mattr_accessor :allow_recovery_from_primary_email, default: true

  # the base controller that all the Auth controllers inherit from
  mattr_accessor :base_controller, default: '::ApplicationController'

  # used internally
  mattr_accessor :forbidden_regexps

  class Error < StandardError; end
  class InvalidConfiguration < Error; end
  class UnauthenticatedRequest < Error; end
  class UnauthorizedRequest < Error; end
  class SuspendedRequest < Error; end
  class ForbiddenRequest < Error; end
  class PasswordUpdateError < Error
    attr_reader :errors
    def initialize(errors)
      @errors = errors
      super("Refusing to update an invalid password")
    end
  end

  def self.base_controller
    @@base_controller.constantize
  end

  autoload :WebToken, __dir__ + "/auth/web_token"
  autoload :AAGUID, __dir__ + "/auth/aaguid"
  autoload :KeyProvider, __dir__ + "/auth/key_provider"
  autoload :SessionVault, __dir__ + "/auth/session_vault"
end
