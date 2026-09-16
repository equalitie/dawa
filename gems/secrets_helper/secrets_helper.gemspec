Gem::Specification.new do |spec|
  spec.name        = "secrets_helper"
  spec.version     = "0.1.0"
  spec.authors     = ["raft authors"]
  spec.summary     = "Useful methods for encrypted URLs, random codes, and encrypted tickets"
  spec.license     = "MIT"
  spec.files = Dir["{app,lib}/**/*", "LICENSE", "README.md"]

  spec.add_dependency('rbnacl')
  spec.add_dependency('openssl')
  spec.add_dependency('securerandom')
  spec.add_development_dependency('sqlite3')
end
