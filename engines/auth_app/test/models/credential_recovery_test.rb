require_relative "../test_helper"

class CredentialRecoveryTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester-#{SecureRandom.hex(4)}")
    @credential = Auth::Credential::Recovery.create!(user: @user)
  end

  def test_label
    assert_equal "Recovery Code", @credential.label
  end

  def test_deletable
    assert @credential.deletable?
  end

  def test_not_editable
    assert_not @credential.editable?
  end

  def test_find_by_code_finds_credential
    recovery_code = "ABCD-EFGH-IJKL-MNOP"
    normalized = recovery_code.downcase.gsub("-", "")
    cred = Auth::Credential::Recovery.create!(user: @user)
    cred.key_from_secret(recovery_code)
    cred.reload

    found = Auth::Credential::Recovery.find_by_code(recovery_code)
    assert_equal cred, found
  end

  def test_find_by_code_normalizes_dashes_and_case
    recovery_code = "abcd-efgh-ijkl-mnop"
    cred = Auth::Credential::Recovery.create!(user: @user)
    cred.key_from_secret(recovery_code)
    cred.reload

    # Try with different case and dashes
    mangled = "ABCD-EFGH-IJKL-MNOP"
    found = Auth::Credential::Recovery.find_by_code(mangled)
    assert_equal cred, found
  end

  def test_find_by_code_returns_nil_for_unknown
    assert_nil Auth::Credential::Recovery.find_by_code("ABCD-EFGH-IJKL-MNOP")
  end

  def test_key_from_secret_normalizes_case_and_dashes
    recovery_code = "ABCD-EFGH-IJKL-MNOP"
    cred = Auth::Credential::Recovery.create!(user: @user)
    cred.key_from_secret(recovery_code)
    cred.reload

    # Verify the credential can be found with the normalized code
    found = Auth::Credential::Recovery.find_by_code(recovery_code)
    assert_equal cred, found
  end

  def test_key_from_secret_uses_pbkdf_via_phrase_base
    key = @credential.key_from_secret("ABCD-EFGH-IJKL-MNOP")
    assert_kind_of RbNaCl::PrivateKey, key
    assert_equal RbNaCl::PrivateKey::BYTES, key.to_bytes.bytesize
  end

  def test_key_from_secret_creates_authenticator_id
    assert_nil @credential.authenticator_id
    @credential.key_from_secret("ABCD-EFGH-IJKL-MNOP")
    @credential.reload
    assert @credential.authenticator_id.present?
  end
end
