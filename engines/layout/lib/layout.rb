
module Layout
  autoload :Theme, __dir__ + "/layout/theme"
  class Engine < ::Rails::Engine
    config.autoload_paths << root.join("lib")

    config.to_prepare do
      ActiveSupport.on_load(:action_controller) do
        include LayoutThemeConcern
      end
    end

    initializer "layout.assets.precompile" do |app|
      app.config.assets.precompile << "layout/application.css"
      Dir.chdir(File.expand_path('../app/assets/', __dir__)) do
        app.config.assets.precompile += Dir["fonts/**/*.woff2"]
        app.config.assets.precompile += Dir["images/**/*.{svg,png,ico,jpg}"]
      end
    end

    initializer "layout.importmap", before: "importmap" do |app|
      app.config.importmap.paths << root.join("config/importmap.rb")
      app.config.importmap.cache_sweepers << root.join("app/javascript")
    end

    initializer "layout.assets" do |app|
      app.config.assets.paths << root.join("app/javascript")
    end
  end
end
