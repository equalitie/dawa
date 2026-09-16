require_relative "../test_helper"

#
# Controller tests for the enrollment flow (EnrollController).
#
# Registering a real passkey goes through the WebAuthn endpoints
# (/auth/webauthn/register_*), which involve a browser + authenticator. For these
# controller tests we stub that out: we drive the enrollment steps and, where a
# registered credential is required, create the Webauthn credential directly and
# mark it registered with a dummy authenticator value.
#
class EnrollControllerTest < ActionDispatch::IntegrationTest
  def unique_username
    "enroll-" + SecureRandom.hex(4)
  end

  # Complete the "name" step via the controller, creating the user + (unregistered)
  # Webauthn credential the way UserForm does. Returns the created user.
  def create_enrolling_user(username: unique_username, display_name: "Enroll Test")
    post enroll_path, params: {
      step: "name",
      user: { username: username, display_name: display_name }
    }
    User.find_by!(username: username)
  end

  # Stub "the passkey was registered": set the credential's public key so
  # credential.registered? => true, without running the WebAuthn protocol.
  def stub_registered_passkey(user)
    credential = user.credentials.webauthn.take!
    credential.update!(authenticator: SecureRandom.random_bytes(64).unpack1("H*"))
    credential
  end

  def create_invite(role)
    Invite.create!(
      max_uses: 1,
      role: role,
      expires_at: 1.week.from_now
    )
  end

  # Drive the full enrollment (accept invite -> name -> credential) for the given
  # invite. Accepting the invite via the join controller sets session[:current_invite]
  # the way a real user would. Returns the finalized user.
  def enroll_via_invite(invite, session:, username: unique_username)
    # join#update sets session[:current_invite] and redirects to the name step
    session.put join_path(invite.code)

    session.post enroll_path, params: {
      step: "name",
      user: { username: username, display_name: "Enroll Test" }
    }
    user = User.find_by!(username: username)
    stub_registered_passkey(user)
    session.put enroll_path, params: { step: "credential", credential: { name: "My Passkey" } }
    user.reload
  end

  def test_start_redirects_to_name_step
    post start_enroll_path, params: { timezone: "America/Los_Angeles" }

    assert_redirected_to step_enroll_path(step: "name")
  end

  def test_show_name_step_renders_form
    get step_enroll_path(step: "name")

    assert_response :success
    assert_select "form[action='#{enroll_path}']" do
      assert_select "input[name='step'][value='name']"
      assert_select "input[name='user[username]']"
    end
  end

  def test_create_creates_inactive_user_with_webauthn_credential
    assert_difference("User.count", 1) do
      assert_difference("Auth::Credential.count", 1) do
        @created_user = create_enrolling_user
      end
    end

    refute @created_user.is_active?
    refute @created_user.is_finalized?
    assert_equal 1, @created_user.credentials.webauthn.count

    # redirected to the credential (passkey) step
    assert_redirected_to step_enroll_path(step: "credential")
  end

  def test_credential_step_shows_passkey_registration_ui
    create_enrolling_user

    get step_enroll_path(step: "credential")

    assert_response :success
    # the passkey registration UI is rendered (actual registration stubbed in tests)
    assert_select "[data-controller='webauthn']"
  end

  def test_update_credential_finalizes_enrollment_with_registered_passkey
    user = create_enrolling_user
    stub_registered_passkey(user)

    put enroll_path, params: { step: "credential", credential: { name: "My Passkey" } }

    user.reload
    assert user.is_active?
    assert user.is_finalized?
    assert user.credentials.webauthn.take&.is_active?
    assert_redirected_to home_url
  end

  def test_destroy_removes_inactive_user
    user = create_enrolling_user

    assert_difference("User.count", -1) do
      delete enroll_path
    end

    assert_nil User.find_by(id: user.id)
    assert_redirected_to root_url
  end

  def test_enroll_with_user_invite_creates_a_normal_user
    invite = create_invite("user")

    user = enroll_via_invite(invite, session: open_session)

    assert user.is_active?
    refute user.is_admin?
    assert_equal invite, user.invite
  end

  def test_enroll_with_admin_invite_creates_an_admin_user
    invite = create_invite("admin")

    user = enroll_via_invite(invite, session: open_session)

    assert user.is_active?
    assert user.is_admin?
    assert_equal invite, user.invite
  end
end
