#
# vaults are a Hash, encrypted and stored in the user_credentials.vault column.
#
# vaults are encrypted as a SimpleBox for sending messages
# FROM the app public key TO the vault private key
#
# Public info that is set to the browser before authentication:
#
# * vault_seed
# * webauthn_id (authenticator_id)
#
module Auth
  class Credential < ApplicationRecord
    self.table_name = "user_credentials"
    belongs_to :user
    has_many :attempts, class_name: "Auth::Attempt", dependent: :nullify

    scope :active,   -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
    scope :webauthn, -> { where(type: "Auth::Credential::Webauthn") }
    scope :recovery, -> { where(type: "Auth::Credential::Recovery") }
    scope :phrase,   -> { where(type: "Auth::Credential::Phrase") }
    scope :visible,  -> { where(type: ["Auth::Credential::Webauthn", "Auth::Credential::Recovery", "Auth::Credential::Demo"]) }
    scope :without_encryption, -> { where(vault_public_key: nil) }

    def self.find_by_webauthn_id(id)
      where(authenticator_id: id).take
    end

    def self.model_name
      ActiveModel::Name.new(self, nil, "Credential")
    end

    def registered?
      authenticator.present?
    end

    def encryption?
      vault_public_key.present?
    end

    def supports_prf?
      false
    end

    def deletable?
      true
    end

    def editable?
      false
    end

    #
    # override with subclasses
    #
    def label
    end
    def comment
    end

    #
    # Returns the private key needed to unlock
    # this credential's vault. If the public_key has
    # not yet been saved to this record, it is saved now.
    #
    # @param secret [Binary] The seed used to generate the private key.
    #   The secret is derived from webauthn PRF (when supported),
    #   or from a user supplied encryption phrase.
    #
    def vault_private_key(secret)
      private_key = key_from_secret(secret)
      return nil unless private_key
      if self.vault_public_key
        if self.vault_public_key != private_key.public_key
          raise ArgumentError, "Incorrect secret used to generate private key"
        end
      else
        self.update(vault_public_key: private_key.public_key)
      end
      private_key
    end

    def init_vault(secret)
      vault_private_key(secret)
    end

    def reset_vault(secret)
      self.vault_public_key = nil
      vault_private_key(secret)
    end

    def read_vault(secret)
      return nil unless secret
      return nil unless private_key = vault_private_key(secret)
      return {}  unless self.vault

      sender     = Auth.app_public_key
      recipient  = private_key
      box        = RbNaCl::SimpleBox.from_keypair(sender, recipient)
      serialized = box.decrypt(self.vault)
      hash = JSON.parse(serialized)
      hash = hash.transform_values do |value|
        if value.starts_with?("0x")
          [value[2..-1]].pack("H*") # hex to binary
        else
          value
        end
      end
      hash
    end

    def update_vault(hash, method: :update)
      return false unless vault_public_key
      hash = hash.to_h.transform_values do |value|
        if value.encoding == Encoding::BINARY
          "0x" + value.unpack("H*").first # binary to hex
        else
          value
        end
      end
      serialized = JSON.generate(hash)
      sender     = Auth.app_private_key
      recipient  = vault_public_key
      box        = RbNaCl::SimpleBox.from_keypair(recipient, sender)
      vault      = box.encrypt(serialized)
      self.send(method, {vault: vault})
    end

    def update_vault!(hash)
      update_vault(hash, method: :update!)
    end

    #
    # Can be overwritten by subclasses if they have different
    # key requirements.
    #
    def key_from_secret(secret)
      Auth.key_provider.private_key(secret, salt: Auth.salt)
    end
  end
end
