#
# This is the class responsible for exposing encryption keys to
# the rest of the application. For now, we just store the keys in
# the session. The session record itself is encrypted using the
# app_key.
#
# Keys are binary strings, but sessions cannot serialize binary strings.
# So, keys are converted to hex when being written to the session
# and converted to binary when read from the session.
#

module Auth
  class SessionVault
    def initialize(session=nil)
      if session.nil?
        @session = { vault: {} }
      elsif session.is_a?(Auth::Session)
        @session = { vault: session.data["vault"] }
      elsif session.is_a?(ActionDispatch::Request::Session)
        @session = session
      elsif session.is_a?(Hash)
        @session = session
      end
      @session[:vault] ||= {}
    end

    #
    # replace the current vault
    #
    def set(hash)
      @session[:vault] = {}
      if hash
        @session[:vault] = hash.to_h.transform_values do |v|
          hex(v)
        end
      end
    end

    #
    # merge with the current vault
    #
    def merge(hash)
      @session[:vault] ||= {}
      if hash
        hash.to_h.each do |k, v|
          @session[:vault][k] = hex(v)
        end
      end
    end

    def exists?
      @session[:vault].present?
    end

    def to_h
      @session[:vault] || {}
    end

    def get(obj)
      raise ArgumentError, "cannot lookup nil in session vault" unless obj
      key = @session[:vault][obj_id(obj)]
      if key.nil?
        raise StandardError.new, "Vault is empty"
      else
        binary key
      end
    end

    def put(obj, secret)
      @session[:vault][obj_id(obj)] = hex(secret)
    end

    def has?(obj)
      raise ArgumentError, "cannot lookup nil in session vault" unless obj
      !!@session[:vault][obj_id(obj)]
    end

    def create_new_key(obj)
      put(obj, Auth.key_provider.random_key)
    end

    private

    def binary(str)
      if str.encoding != Encoding::BINARY
        [ str ].pack("H*") # hex to binary
      else
        str
      end
    end

    def hex(str)
      if str.encoding == Encoding::BINARY
        str.unpack("H*").first # binary to hex
      else
        str
      end
    end

    def obj_id(obj)
      if obj.is_a?(Integer)
        [ "workspace", obj ].join("/")
      else
        [ obj.model_name.element, obj.id ].join("/")
      end
    end
  end
end
