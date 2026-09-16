module Auth
  class Engine < ::Rails::Engine
    isolate_namespace Auth

    initializer "auth.importmap", before: "importmap" do |app|
      app.config.importmap.paths << root.join("config/importmap.rb")
      app.config.importmap.cache_sweepers << root.join("app/javascript")
    end

    initializer "auth.assets" do |app|
      app.config.assets.paths << root.join("app/javascript")
    end

    #
    # use activerecord session store
    #
    config.before_initialize do
      Rails.application.config.session_store :active_record_store, key: Conf.session_key, secure_session_only: Rails.env.production?
    end
    config.after_initialize do
      ActionDispatch::Session::ActiveRecordStore.session_class = Auth::Session
    end
  end
end
