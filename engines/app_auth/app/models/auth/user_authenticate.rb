#
# A concern that handles the behavior of user authentication.
#
module Auth
  module UserAuthenticate
    extend ActiveSupport::Concern

    included do
      store_accessor :data, :webauthn_id
      has_many :credentials, class_name: "Auth::Credential", dependent: :destroy
      has_many :attempts, class_name: "Auth::Attempt", dependent: :destroy
    end
  end
end
