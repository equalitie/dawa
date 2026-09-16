
unless ENV["SKIP_CONF"]
  key_provider                 = Auth.key_provider
  Conf.data["secret_key_base"] = key_provider.to_binary(Rails.application.secret_key_base)
  Conf.data["salt"]            = key_provider.to_binary(Conf.salt)

  Auth.salt = Conf.salt
  Auth.app_private_key  = key_provider.private_key(Conf.secret_key_base, salt: Conf.salt)
  Auth.app_public_key   = Auth.app_private_key.public_key

  Auth.origin = Conf.site_domain
  Auth.relaying_party = Conf.site_title
end
