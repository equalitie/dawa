module Auth
  class Credential::Recovery < Auth::Credential::Phrase
    def generate
      Secrets::RandomCode.create(16, 4) # 128 bits (16 chars, split every 4)
    end

    def self.find_by_code(recovery_code)
      code = recovery_code.downcase.gsub("-", "")
      self.where(authenticator_id: id_from_code(code)).take
    end

    def label
      "Recovery Code"
    end

    def deletable?
      true
    end

    def editable?
      false
    end

    #
    # for recovery codes, we don't care about case and we remove the "-" splits
    #
    def key_from_secret(recovery_code)
      code = recovery_code.downcase.gsub("-", "")
      if authenticator_id.nil?
        self.update_column(:authenticator_id, self.class.id_from_code(code))
      end
      super(code)
    end

    private

    #
    # create a non-secure id that is used to fetch the recovery record.
    # SHA1 is 40 hex chars, so should fit in authenticator_id column.
    #
    def self.id_from_code(code)
      OpenSSL::HMAC.hexdigest("SHA1", Conf.secret_key_base, code)
    end
  end
end
