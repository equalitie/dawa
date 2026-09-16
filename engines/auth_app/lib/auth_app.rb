require "active_record/session_store"
require "webauthn"
require "browser/browser"
require_relative "auth/engine"

module Auth
  # required: these must be defined in config/initializers
  mattr_accessor :origin # domain name. this CANNOT be changed.
  mattr_accessor :relaying_party # string presented to the user (defaults to origin)

  # encryption
  mattr_accessor :key_provider
  mattr_accessor :app_public_key
  mattr_accessor :app_private_key
  mattr_accessor :salt

  # login page
  mattr_accessor :login_url, default: "auth.new_session_url"

  # home when authenticated
  mattr_accessor :home_url, default: "main_app.home_url"

  # home when not authenticated
  mattr_accessor :root_url, default: "main_app.root_url"

  # keys that are preserved in the session when the user authenticates.
  # everything else is reset.
  mattr_accessor :preserve_session_keys, default: [ :locale, :timezone ]

  mattr_accessor :user_session_idle_timeout, default: "4 hours"
  mattr_accessor :user_session_max_lifetime, default: "20 hours"

  # array of usernames that cannot be used by normal users
  mattr_accessor :forbidden_usernames, default: %w(
    admin anon contact hello help help-desk info root security security-staff staff support support-staff sysadmin team web-master
  )

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

  # argon2 parameters
  # opslimit is CPU cost, 3..10
  # memlimit is memory cost, in bytes
  mattr_accessor :argon2_opslimit, default: 5 # the 3..10 the CPU cost
  mattr_accessor :argon2_memlimit, default: 1_073_741_824 # (1 gb)

  # Whether to update user#last_login_on  after sucessfuly log in
  mattr_accessor :update_last_login, default: true

  # the base controller that all the Auth controllers inherit from
  mattr_accessor :base_controller, default: '::ApplicationController'

  # used internally (derived from forbidden_usernames)
  mattr_accessor :forbidden_regexps

  # jwt configuration (replaces Conf references)
  mattr_accessor :jwt_secret
  mattr_accessor :jwt_header, default: "HTTP_AUTHORIZATION"
  mattr_accessor :jwt_expiry, default: "1 hour"

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
