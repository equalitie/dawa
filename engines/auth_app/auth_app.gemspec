$:.push File.expand_path("lib", __dir__)

Gem::Specification.new do |spec|
  spec.name        = "auth_app"
  spec.version     = "0.1.0"
  spec.authors     = ["waxw.ing"]
  spec.summary     = "A mountable Rails Engine providing basic authentication and session management."

  spec.files = Dir["{app,config,db,lib}/**/*", "LICENSE", "Rakefile", "README.md"]

  spec.add_dependency "activerecord-session_store"
  spec.add_dependency "webauthn", ">= 3.4.3"
  spec.add_dependency "json"

  # crypto
  spec.add_dependency "jwt"
  spec.add_dependency "rbnacl"
  spec.add_dependency "openssl"

  # views
  spec.add_dependency "browser" # parse browser's user-agent string
  spec.add_dependency "haml-rails" # haml view templates
  spec.add_dependency "turbo-rails" # support turbo stream responses
end
