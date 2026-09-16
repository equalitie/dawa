require_relative "../test_helper"

class SessionControllerTest < ActionDispatch::IntegrationTest
  def setup
    User.create!(username: "testuser")
  end

  def test_session_updated_at
    post test_session_path, params: { username: "testuser" }
    assert session["user_id"]
    assert cookies["id"]

    session_record = Auth::Session.find_by_public_id(cookies["id"])
    assert session_record

    assert_equal session["user_id"], session_record.data["user_id"]
    # assert session["vault"]
    # assert_equal session["vault"], session_record.data["vault"]

    updated_at = session_record.updated_at

    get home_path
    session_record.reload
    assert_equal updated_at, session_record.updated_at

    travel_to 2.minutes.from_now do
      put test_session_path, params: { visited_at: Time.current.iso8601 }
      session_record.reload
      assert updated_at < session_record.updated_at, "#{updated_at} < #{session_record.updated_at}"
    end
  end

  # def test_session_encrypted
  #   creator.user
  #   assert_difference "Auth::Session.count" do
  #     post demo_session_path, params: { username: "testy" }
  #   end
  #   session = Auth::Session.find_by_public_id(cookies[:id])

  #   assert session.data.is_a?(Hash)
  #   assert_equal 1, session.data["user_id"]

  #   binary_ciphertext = nil
  #   session.load_key do
  #     ciphertext = session.read_attribute_before_type_cast(:data)
  #     binary_ciphertext = session.column_for_attribute("data").send(:cast_type).deserialize(ciphertext)
  #     cleartext = Auth.encryptor.decrypt(binary_ciphertext, key: :session_key, binary: true)
  #     assert cleartext.present?
  #     assert cleartext.index('"user_id":')
  #     json = JSON.parse(cleartext)
  #     assert json.is_a?(Hash)
  #     assert_equal 1, json["user_id"]
  #   end

  #   # session_key should be cleared
  #   cleartext = Auth.encryptor.decrypt(binary_ciphertext, key: :session_key)
  #   assert !cleartext.index('"user_id":')
  # end

  def disabled_test_cleanup_vault
    # pre-seed the keys so they match our vault
    key_for_workspace(1, VAULT["workspace/1"])
    key_for_workspace(2, VAULT["workspace/2"])

    user = creator.user
    assert_equal [ 1 ], user.ws_ids

    # ensure the testing parameters have not changed
    assert_equal Auth.encryptor.app_public_key.to_s, CREDENTIAL_PARAMETERS[:app_public_key]
    assert_equal Conf.salt.to_s, CREDENTIAL_PARAMETERS[:app_salt]

    # create webauthn credential
    cred = user.credentials.create!(CREDENTIAL)

    # verify vault contents
    prf_response = Base64.urlsafe_decode64(PRF)
    vault = cred.read_vault(prf_response)

    assert vault, "vault should exist"
    assert_equal VAULT, vault

    # simulate `post auth.initiate_session_path`
    set_session(
      verify_user_id: user.id,
      verify_challenge: INITIATE_RESPONSE["challenge"]
    )

    # webauthn verify
    post auth.verify_session_path, params: VERIFY_REQUEST
    hsh = JSON.parse(response.body)
    assert_equal "ok", hsh["status"], "verify response should be ok (was #{hsh.inspect})"

    # confirm key is removed from vault
    expected_vault = VAULT.slice("workspace/1")
    new_vault = cred.reload.read_vault(prf_response)
    assert_equal expected_vault, new_vault, "new vault should not have workspace 2 key"
  end

  VAULT = {
    "workspace/1" => "6b34f87ccd0982220a0a2e38834e22e82bcd1f2a823dd4e97e14c93aa30270e2",
    "workspace/2" => "e376c4e99510c9148101b972ffebda57ba28114efa05c7494933e1b949699d24"
  }

  CREDENTIAL_PARAMETERS = {
    app_public_key: "e\xA2\xE6\x1A\xC6{Z\xF6\xE3\x1C\xA7i\x06\xBDc\xEB\xF8\xA4\xDB\x1Di\xF0\t\x8F\fE#3\r\x19\x8E4".b,
    app_salt: "hgt\x98r\x96\xDEob\x00Ki\x13e\xD0\xE7e\xAC\xBF\x01\xADx\x17\xC4>\xAB<|#\xCD\xE4\xC3".b
  }

  #
  # created by doing:
  #
  # cred = Auth::Credential.create(user: @@user)
  # cred.init(Base64.urlsafe_decode64(PRF))
  # cred.update_vault(VAULT)
  # cred.attributes
  #
  CREDENTIAL = {
    type: "Auth::Credential::Webauthn",
    is_active: true,
    authenticator: "pQECAyYgASFYIBfMCG-klgR8JLG4dVA6GS-HMro6UZQtkwKUZZMfDlqUIlgg-x9egQZTevQDVIEd55Ih-hz1pDeflWF6cuxZV1Qspwo",
    authenticator_id: "dWWsqVrbpigjj_e1qzaVg88UofIF7WG4jMZLC7H9Ru-4nU9hx6L3-m-pYP5yl7HagMfc2-KWWgetQckMclZMiQ",
    vault: "\x8F\x11\xA1\x0E@\xAE}\x0Fv\xCD\x05\xF9\x81OB|\x8B\xF4a\x14\x14!\xAA\xC4x>\a8<\xE71\xC7b/\xC0\x0E\xF8\x8E'\e(JI\x9C)=~\xB2hs8n\xF2\xE8\xF8\xF3\x9E\xF6(~\xB1$\xDB:\ft\x95\xAB\xA0 \xC5\xA5U\xD427P\xBD\xB0\x1E\x9A\xD6\f\xF9\x86\x13\e\ao&\xA5a\xBE\xE6\xE9)\xE5\x88\xF2Z\xBFE\x17\xFBd\xA7\xC4s\x01R\xB2K\x02\xA5\x98\x12Xl\x94\xD5[)@\x18y\x8CG\xEAJ\xE4\xC8r\xA0\xC3!\xD91\x98*\xAD\xB0\xD42F\x06!\xB1/\xD4$\x93B\x123\x99\x8FY\xF4TH\x1C\xA4\xB2\xC7\xB2\xDA\xCE\xC0o\xAA\xA1da\xC3h\x16\xA8\xE0\xE4\xB2\xDB6[\x9C\xA6\x9E\x15RL*\xC3\x10\xC9\x10`\x8D#\x03\x1CF[\xBDB",
    vault_public_key: "\xA9g\xB6\xA7Nt0\xC1\x9At5\x95\xA2\xBF\x10\xD8!\xD2\xE1Z<S1\xA5(2\xEE\xF3\xA6\xF3\x8D)",
    vault_seed: "",
    data: {
      "aaguid": "2fc0579f-8113-47ea-b116-bb5a8db9202a",
      "sign_count": "0",
      "prf_enabled": true
    }
  }

  WEBAUTHN_ID = "dWWsqVrbpigjj_e1qzaVg88UofIF7WG4jMZLC7H9Ru-4nU9hx6L3-m-pYP5yl7HagMfc2-KWWgetQckMclZMiQ"

  INITIATE_REQUEST = {
    "login" => "testy"
  }

  INITIATE_RESPONSE = {
    "challenge" => "SBqsKCAg8ANrOrPPmt216txwutv2Me68Q8Lcac9pZIk",
    "timeout" => 120000,
    "extensions" => {
       "prf" => {
         "evalByCredential" => {
           "dWWsqVrbpigjj_e1qzaVg88UofIF7WG4jMZLC7H9Ru-4nU9hx6L3-m-pYP5yl7HagMfc2-KWWgetQckMclZMiQ" => {
             "first" => "HhHhWByAwGI85Mr7H__eg3mIX2ohTmNwsPe9jSRK8I0="
           }
         }
       }
    },
    "allowCredentials" => [ {
      "type" => "public-key",
      "id" => "dWWsqVrbpigjj_e1qzaVg88UofIF7WG4jMZLC7H9Ru-4nU9hx6L3-m-pYP5yl7HagMfc2-KWWgetQckMclZMiQ"
    } ],
    "userVerification" => "required"
  }

  PRF = "leyhc5qOCQlzt6NJw-XGkryaO_ryoHr9WnMGSGKaDoA="

  VERIFY_REQUEST = {
    "credential" => {
      "authenticatorAttachment" => "cross-platform",
      "clientExtensionResults" => { "prf" => {} },
      "id" => "dWWsqVrbpigjj_e1qzaVg88UofIF7WG4jMZLC7H9Ru-4nU9hx6L3-m-pYP5yl7HagMfc2-KWWgetQckMclZMiQ",
      "rawId" => "dWWsqVrbpigjj_e1qzaVg88UofIF7WG4jMZLC7H9Ru-4nU9hx6L3-m-pYP5yl7HagMfc2-KWWgetQckMclZMiQ",
      "response" => {
        "authenticatorData" => "SZYN5YgOjGh0NBcPZHZgW4_krrmihjLHmVzzuoMdl2OFAAAAGKFraG1hYy1zZWNyZXRYMAeEU6CvqZTaJLQVCzIRW8OLHPAWiYOvYs-ekaOMbFQzSkn-zH9gvmRpdXK7LCBDiw", "clientDataJSON" => "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoiU0Jxc0tDQWc4QU5yT3JQUG10MjE2dHh3dXR2Mk1lNjhROExjYWM5cFpJayIsIm9yaWdpbiI6Imh0dHA6Ly9sb2NhbGhvc3Q6MzAwMCIsImNyb3NzT3JpZ2luIjpmYWxzZX0", "signature" => "MEUCIQCmubbcIvR4tvk-mfyp1fNmjApmSUVb0nUJqDYF5X3OMQIgZDLbLEVMcXdy40F1I2fYpltZ662EFUnp1Hzvmv2-1o0"
      },
      "type" => "public-key"
    },
    "client_extension_results" => {
      "prf" => {
        "results" => {
          "first" => "leyhc5qOCQlzt6NJw-XGkryaO_ryoHr9WnMGSGKaDoA="
        }
      }
    }
  }
end
