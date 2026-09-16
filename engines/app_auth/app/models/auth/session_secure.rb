#
# An sql session store with support for encrypted data.
# Require raft_encryption
#
module Auth
  #
  # find_by_session_id() is in a separate module that gets prepended to
  # Auth::Session. we do this to ensure that the dynamic finder is not called
  # instead, which sometimes happens in development mode when classes get
  # reloaded.
  #
  module SessionCustomFinders
    def find_by_session_id(id)
      id, session_key = Auth::Session.split_session_id(id)

      if defined?(Raft::Encryption)
        Raft::Encryption.key_context(session_key, name: :session_key) do
          session = where(session_id: id).take
          if session
            session.session_key = session_key
            session.attributes # load while session key is active
          end
          return session
        end
      else
        return where(session_id: id).take
      end
      nil
    end

    #
    # session ids have a public and private variant:
    # the public id is what is stored in the cookie.
    # the private id is how the session record is indexed in the database.
    # the reason for this is to prevent a client from being able to hijack
    # a session by using timing attacks to guess a session id
    #
    def find_by_public_id(public_session_id)
      session_id_object = Rack::Session::SessionId.new(public_session_id)
      private_id = session_id_object.private_id
      find_by_session_id(private_id)
    end
  end

  class SessionSecure < Session
    singleton_class.prepend(SessionCustomFinders)

    include Raft::Encryptable
    raft_encrypts :data, key: :session_key

    attr_accessor :session_key
    around_save :load_key

    #
    # We use part of the private session id as the session encryption key
    # by splitting the session id in half.
    #
    # example session ids:
    #   public: 32 char hex 76f6e251f62a03213cde6f6440003661
    #   private: 64 char hex, 3 char prefix 2::846e52c36cb2b1590e804ffc8d84b38f9544e7e4b38a4610327ab2392969c391
    #
    def self.split_session_id(session_id)
      return [ nil, nil ] unless session_id.length == 67
      id   = session_id[0..34]
      seed = session_id[35..66]
      session_key = Auth.key_provider.key(secret: seed, salt: Conf.salt)
      [ id, session_key ]
    end

    def initialize(args)
      args[:session_id], self.session_key = Auth::Session.split_session_id(args[:session_id])
      super
    end

    # load a session key, yield the block to perform some
    # encryption or decryption, then clear the session key.
    def load_key(session_key = nil)
      self.session_key ||= session_key
      Raft::Encryption.session_key = self.session_key
      yield if block_given?
      self.attributes # force loading attributes while session key is active
      Raft::Encryption.session_key = nil
    end

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
  end
end
