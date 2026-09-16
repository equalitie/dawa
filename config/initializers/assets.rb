# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# dartsass-rails writes compiled CSS (e.g. application.scss -> application.css)
# to app/assets/builds, which Propshaft must include as an asset load path so
# `assets:precompile` bundles the output into public/assets. dartsass-rails
# registers this normally; ensure it is present here to avoid shipping images
# without the compiled stylesheet.
Rails.application.config.assets.paths << Rails.root.join("app", "assets", "builds")
