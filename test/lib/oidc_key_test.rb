require "test_helper"

class OidcKeyTest < ActiveSupport::TestCase
  #
  # A real P-521 (secp521r1) EC private key body in its flattened env-var form
  # (no gating, no newlines) as produced by `rake dawa:required`.
  #
  FLAT_BODY = "MIHcAgEBBEIAeYSlQ3biOquBl9ZMZ3QwqYczkfRbFKOgnR366Ahsxz58ulLRnJB/NilKvm9athqd0E8OwnIJsvowi7eE7ftkH1CgBwYFK4EEACOhgYkDgYYABAB2qPATHj6yeagT02RC/mTZAebN/AmtnrJFV56bJsbUavbs2a5tskp7ojHueGBnL8LTQNXINe0AaPBL0PI2jtw/KAHYqL+grfXafltQea3BHP7rBV4X3yHixJ/wMcCLVs6/0xNYDkEtKFUIBHOF8h04rpp9s/Gf1SInPBwrQqSP1XrWSw=="

  def test_passes_through_a_complete_gated_multiline_pem
    pem = "-----BEGIN EC PRIVATE KEY-----\n#{wrap(FLAT_BODY)}\n-----END EC PRIVATE KEY-----"
    normalized = Dawa::OidcKey.to_pem(pem)

    assert normalized.include?("-----BEGIN EC PRIVATE KEY-----")
    assert normalized.include?("-----END EC PRIVATE KEY-----")
    assert parsed?(normalized)
  end

  def test_rewraps_a_flat_ungated_body
    normalized = Dawa::OidcKey.to_pem(FLAT_BODY)

    assert normalized.start_with?("-----BEGIN EC PRIVATE KEY-----\n")
    assert normalized.end_with?("-----END EC PRIVATE KEY-----\n")
    assert parsed?(normalized)
    # body is wrapped at the PEM line width
    assert normalized.lines.all? { |l| l.chomp.empty? || l.start_with?("---") || l.chomp.length <= 64 }
  end

  def test_rewraps_a_literal_backslash_n_env_value
    single_line = wrap(FLAT_BODY).gsub("\n", "\\n") # simulate ".env"-style escaping
    normalized = Dawa::OidcKey.to_pem(single_line)

    assert parsed?(normalized)
  end

  def test_empty_value_returns_empty
    assert_equal "", Dawa::OidcKey.to_pem(nil)
    assert_equal "", Dawa::OidcKey.to_pem("")
  end

  private

  def wrap(body)
    body.scan(/.{1,64}/).join("\n")
  end

  def parsed?(pem)
    OpenSSL::PKey::EC.new(pem)
    true
  rescue OpenSSL::PKey::PKeyError
    false
  end
end
