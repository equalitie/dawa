# Reference the logo as a managed pipeline asset so Propshaft resolves/hashes
# it and (unlike a hard-coded root-absolute path under public/) it doesn't
# emit an "Unable to resolve ..." warning during assets:precompile.
Layout::Theme.configure do |theme|
  theme.favicon_url = ActionController::Base.helpers.asset_path("dcomms-logo.svg")
end
