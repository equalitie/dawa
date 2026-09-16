#
# A concern that handles the behavior of user authentication.
#
module Auth
  module UserAuthenticate
    extend ActiveSupport::Concern

    included do
      store_accessor :data, :webauthn_id
      has_many :attempts, class_name: "Auth::Attempt", dependent: :destroy

      has_many :credentials, class_name: "Auth::Credential", dependent: :destroy do
        def update_vaults(vault_hash)
          self.each do |cred|
            cred.update_vault(vault_hash)
          end
        end
        def update_vaults!(vault_hash)
          self.each do |cred|
            cred.update_vault!(vault_hash)
          end
        end
      end

    end
  end
end
