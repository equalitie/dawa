
if ENV["SKIP_CONF"]
  Auth.skip_configuration_checks = true
else
  key_provider                 = Auth.key_provider
  Conf.data["secret_key_base"] = key_provider.to_binary(Rails.application.secret_key_base)
  Conf.data["salt"]            = key_provider.to_binary(Conf.salt)

  Auth.home_url = "main_app.root_url"
  Auth.login_url = "main_app.login_url"

  Auth.salt = Conf.salt
  Auth.app_private_key  = key_provider.private_key(Conf.secret_key_base, salt: Conf.salt)
  Auth.app_public_key   = Auth.app_private_key.public_key
  Auth.origin = Conf.site_public_url
  Auth.relaying_party = Conf.site_title
end
