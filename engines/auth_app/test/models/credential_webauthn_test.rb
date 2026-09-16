require_relative "../test_helper"

class CredentialWebauthnTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester")
    @credential = Auth::Credential::Webauthn.create!(user: @user, is_active: true)
  end

  # FIXME: test that label returns the aaguid name when aaguid is present
  def test_label_from_aaguid
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that label returns "Passkey" when aaguid is nil
  def test_label_default
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that comment returns "Automatic Encryption" when encryption? is true
  def test_comment_encrypted
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that comment returns "Phrase Required" when encryption? is false
  def test_comment_phrase_required
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that supports_prf? returns the prf_enabled value
  def test_supports_prf
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that editable? is true only when encryption? is false
  def test_editable_when_not_encrypted
    skip "Not yet implemented"
    assert true
  end
end
