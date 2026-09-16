require_relative "../test_helper"

class CredentialsControllerTest < ActionDispatch::IntegrationTest

  def setup
    @user = User.create!(username: "crow")
  end

  def test_index
    login_as(@user)
    get auth.credentials_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
  end

  # FIXME: test that GET edit renders the credential form for a given credential
  def test_edit
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that PUT update activates a credential and redirects to credentials index
  def test_update_activate
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that PUT update with encryption_phrase creates a phrase credential
  def test_update_with_phrase
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that POST create with type "webauthn" creates a Webauthn credential
  def test_create_webauthn
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that POST create with type "recovery" creates a Recovery credential
  def test_create_recovery
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that DELETE destroy removes the credential
  def test_destroy
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that DELETE destroy with last non-encryption credential also destroys phrase credential
  def test_destroy_removes_orphaned_phrase
    skip "Not yet implemented"
    assert true
  end
end
