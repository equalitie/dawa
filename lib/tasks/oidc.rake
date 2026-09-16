#
# Tasks to generate and manage the RSA private key used for Doorkeeper's
# OpenID Connect `signing_key` (see config/initializers/doorkeeper_openid_connect.rb).
#
require "openssl"

namespace :oidc do
  desc "Generate an RSA private key in PEM format for the OIDC signing_key"
  task :generate_key_rsa, [ :out ] => :environment do |_task, args|
    out = args[:out] || "config/oidc_signing_key.pem"
    bits = (ENV["OIDC_KEY_BITS"] || 3072).to_i
    raise "OIDC_KEY_BITS must be at least 3072" if bits < 3072

    key = OpenSSL::PKey::RSA.new(bits)

    File.write(out, key.to_pem)

    puts "Wrote #{bits}-bit RSA private key to #{out}"
    puts "PEM is %.1f KiB (unencrypted)" % (File.size(out).to_f / 1024)
    puts
    puts "To use it, set Doorkeeper config in doorkeeper_openid_connect.rb:"
    puts "  signing_key File.read(Rails.root.join(#{out.inspect}))"
    puts
    puts "Keep this file secret and OUT of version control."
    puts "(It is referenced by name by other tasks; see the fingerprint task below.)"
  end

  desc "Generate an ES512 (P-521) ECDSA private key in PEM format for the OIDC signing_key"
  task :generate_key_es512 => :environment do |_task, args|
    # ES512 in OIDC maps to the P-521 (secp521r1) curve, signing with SHA-512.
    key = OpenSSL::PKey::EC.generate("secp521r1")

    puts "P-521 (ES512) ECDSA private key:"
    puts
    puts key.to_pem.gsub(/^--.*--$/, "").gsub("\n", "")
    puts
    puts "To use it, set env OPENID_PRIVATE_KEY or add to config/config.yml"
  end

  desc "Print the SHA-256 fingerprint / `kid` of the signing key"
  task :fingerprint, [ :path ] => :environment do |_task, args|
    path = args[:path] || "config/oidc_signing_key.pem"
    key = OpenSSL::PKey::RSA.new(File.read(path))
    pub = key.public_key.to_der
    kid = Digest::SHA256.hexdigest(pub)
    puts "path:  #{path}"
    puts "bits:  #{key.n.num_bits}"
    puts "kid:   #{kid}"
    puts "SHA-1: #{Digest::SHA1.hexdigest(pub)}"
  end
end
