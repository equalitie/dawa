#
# 512 bit keys: 64 bytes, 128 hex chars
# 256 bit keys: 32 bytes, 64 hex chars
# 128 bit keys: 16 bytes, 32 hex charts
#
# SECRETS VS KEYS
#
# For our purposes:
#
# * SECRET is anything that is private information that is used to create a key.
#   Typical secrets will be configured random hex in an ENV variable, a user encryption phrase,
#   or the result of a WebAuthn PRF extension.
#
# * KEY is used directly for encryption. It is has been mixed with a SALT, and is always a BINARY string.
#
# All keys are stored as 512 bits, and then truncated when used.
#

require "openssl"
require "rbnacl"

module Auth
  class KeyProvider
    DEFAULT_BYTES=64

    def random_key()
      SecureRandom.random_bytes(DEFAULT_BYTES)
    end

    #
    # suitable for random secrets
    #
    def key(secret:, salt:, bytes: DEFAULT_BYTES)
      derive_key(
        to_binary(secret, bytes: bytes),
        to_binary(salt, bytes: bytes),
        bytes: bytes
      )
    end

    #
    # suitable for user created secrets
    #
    def pb_key(secret:, salt:, bytes: DEFAULT_BYTES)
      derive_pb_key(
        secret,
        to_binary(salt, bytes: pb_key_salt_bytes),
        bytes: bytes
      )
    end

    def pb_key_salt_bytes
      RbNaCl::PasswordHash::Argon2::SALTBYTES
    end

    def private_key(secret_or_key, salt: nil)
      if secret_or_key.encoding == Encoding::BINARY
        key_seed = secret_or_key
      else
        key_seed = key(
          secret: secret_or_key,
          salt: salt,
          bytes: RbNaCl::PrivateKey::BYTES
        )
      end
      RbNaCl::PrivateKey.new(key_seed)
    end

    def to_binary(str, bytes: DEFAULT_BYTES)
      if str.nil? || str == ""
        raise ArgumentError, "Secret is empty"
      end
      if str.encoding != Encoding::BINARY || str.downcase =~ /\A[a-f0-9]+\z/
        bin = [str[0..((bytes*2)-1)]].pack("H*")
      else
        bin = str
      end
      if bin.length < bytes
        raise ArgumentError, "Secrets must be at least #{bytes} bytes (or string of hex chars [0-F]+, >=#{bytes * 2} length). Received: #{str.inspect}"
      end
      bin
    end

    private

    #
    # HKDF is used for deriving a key for symmetric encryption
    # from a random secret and salt. It does not do key stretching
    # like PBKDF2 and is not suitable for creating keys from
    # user generated passwords.
    #
    def derive_key(secret, salt, bytes: DEFAULT_BYTES)
      OpenSSL::KDF.hkdf(secret, salt: salt, info: "auth", length: bytes, hash: "SHA256")
    end

    #
    # password based key derivation, suitable for user supplied passwords.
    #
    def derive_pb_key(secret, salt, bytes: DEFAULT_BYTES)
      salt = salt[0..(pb_key_salt_bytes-1)]
      opslimit = 5
      memlimit = 1_073_741_824 # (1 gb) the maximum bytes used in memory
      RbNaCl::PasswordHash.argon2(
        secret,
        salt,
        opslimit,
        memlimit,
        bytes
      )
    end
  end
end
#
