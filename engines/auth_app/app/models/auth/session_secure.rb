#
# An sql session store with support for encrypted data.
# Require raft_encryption
#
module Auth
  class SessionSecure < Session
    include Raft::Encryptable
    raft_encrypts :data, key: :session_key

    around_save :load_key

    # Override the data accessor to always decrypt using the session_key
    # when reading from the database.
    def data
      if session_key
        Raft::Encryption.key_context(session_key, name: :session_key) do
          return super
        end
      else
        {}
      end
    end

    private

    # load a session key, yield the block to perform some
    # encryption or decryption, then clear the session key.
    def load_key(session_key = nil)
      self.session_key ||= session_key
      Raft::Encryption.session_key = self.session_key
      yield if block_given?
      self.attributes # force loading attributes while session key is active
      Raft::Encryption.session_key = nil
    end
  end
end
