module Secrets
  autoload :EncryptedUrl,   __dir__ + "/secrets/encrypted_url"
  autoload :Endian,         __dir__ + "/secrets/endian"
  autoload :HasCode,        __dir__ + "/secrets/has_code"
  autoload :IntegerEncoder, __dir__ + "/secrets/integer_encoder"
  autoload :RandomCode,     __dir__ + "/secrets/random_code"
  autoload :TinyUrl,        __dir__ + "/secrets/tiny_url"

  if defined?(Rails) && defined?(Rails::Engine)
    class Engine < ::Rails::Engine
      config.to_prepare do
        ActiveSupport.on_load(:active_record) do
          extend Secrets::HasCode::DefineHasCodeMethod
        end
      end
    end
  end
end
