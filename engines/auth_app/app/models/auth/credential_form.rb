module Auth
  class CredentialForm
    include ActiveModel::Model
    include ActiveModel::Translation

    delegate :model_name, to: :@credential
    delegate :to_param, to: :@credential

    delegate_missing_to :@credential

    attr_accessor :encryption_phrase

    def initialize(credential)
      @credential = credential
    end

    def encryption_is_setup?
      if !Auth.encryption
        true # encryption not enabled, so treat is as if it was set up correctly
      elsif encryption?
        true # great! vault created already
      elsif @credential.is_a?(Auth::Credential::Webauthn)
        if prf_enabled
          # prf is enabled but encryption not set up
          false
        else
          # prf not enabled, so we rely on phrase having vault
          phrase = user.credentials.active.phrase.take
          phrase&.encryption?
        end
      end
    end

    def is_recovery?
      @credential.is_a?(Auth::Credential::Recovery)
    end

    def update_phrase_credential!(vault)
      cred = phrase_credential || user.credentials.create!(
        type: "Auth::Credential::Phrase",
        is_active: true
      )
      cred.reset_vault(encryption_phrase)
      cred.update_vault(vault.to_h)
    end

    #
    # the credential to use for encryption phrases, if required
    # must return nil if this is a cred that supports prf.
    #
    def phrase_credential
      return nil unless Auth.encryption
      if !supports_prf?
        @phrase_credential ||= begin
          if @credential.is_a?(Auth::Credential::Phrase) || @credential.is_a?(Auth::Credential::Recovery)
            @credential
          else
            user.credentials.active.phrase.take
          end
        end
      end
    end

    validate :encryption_phrase_presence
    def encryption_phrase_presence
      if Auth.encryption && encryption_phrase == ""
        self.errors.add(:encryption_phrase, :required)
      end
    end

    #
    # true if the credential is completely setup
    #
    def complete?
      registered? && (!Auth.encryption || encryption? || phrase_credential)
    end

    def update(attrs, vault = nil)
      self.assign_attributes(attrs)
      save(vault)
    end

    def save(vault = nil)
      if valid? && @credential.valid? && @credential.save
        if encryption_phrase && vault
          update_phrase_credential!(vault)
        end
        if complete?
          @credential.update(is_active: true)
        end
        true
      else
        self.errors.merge! @credential.errors
        false
      end
    end
  end
end
