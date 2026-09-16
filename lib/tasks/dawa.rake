namespace :dawa do
  desc "Precompile assets"
  task :precompile do
    envs = {
      "SKIP_CONF" => "true",
      "SKIP_DB" => "true",
      "RAILS_ENV" => "production",
      "SECRET_KEY_BASE" => SecureRandom.hex(32),
      "DATABASE_URL" => "sqlite3::memory:"
    }
    # Re-execute the task with the new environment
    env_str = envs.map { |k, v| [ k, "=", '"', v, '"' ].join }.join(" ")
    exec(env_str + " rake assets:precompile")
  end

  desc "Generates a sample of required ENV variables"
  task :required do
    vars = {
      "SITE_TITLE" => "Dawa",
      "SITE_DOMAIN" => "demo.dcomms.dev",
      "SECRET_KEY_BASE" => SecureRandom.hex(64),
      "SALT" => SecureRandom.hex(64),
      "OPENID_PRIVATE_KEY" =>OpenSSL::PKey::EC.generate("secp521r1").to_pem.gsub(/^--.*--$/, "").gsub("\n", "")
    }
    vars.each do |key, value|
      puts [ key, "=", value ].join
    end
  end

end
