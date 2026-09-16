module Auth
  class Engine < ::Rails::Engine
    isolate_namespace Auth

    def self.initialize_session_store(session_id_key = "id")
      # this must be done before the middleware is initialized. This setup could be
      # call from in the app when config/initializers run if we want to allow the
      # app to set the session id.
      Rails.application.config.session_store :active_record_store, key: session_id_key, secure_session_only: Rails.env.production?
    end

    initializer "auth.importmap", before: "importmap" do |app|
      app.config.importmap.paths << root.join("config/importmap.rb")
      app.config.importmap.cache_sweepers << root.join("app/javascript")
    end

    initializer "auth.assets" do |app|
      app.config.assets.paths << root.join("app/javascript")
    end

    #
    # before config/initalizers
    #
    config.before_initialize do
      Auth.key_provider = Auth::KeyProvider.new
      Auth::Engine.initialize_session_store
    end

    #
    # after config/initializers
    #
    config.after_initialize do
      ActionDispatch::Session::ActiveRecordStore.session_class = Auth::Session

      raise ArgumentError, "Auth.origin must be configured" unless Auth.origin
      raise ArgumentError, "Auth.relaying_party must be configured" unless Auth.relaying_party

      WebAuthn.configure do |config|
        config.allowed_origins = [Auth.origin]
        config.rp_name = Auth.relaying_party
      end
    end
  end
end
