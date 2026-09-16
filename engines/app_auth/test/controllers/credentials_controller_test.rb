require_relative "../test_helper"

class CredentialsControllerTest < ActionDispatch::IntegrationTest

  def setup
    once { creator.user }
  end

  def test_index
    login_as
    get auth.credentials_path
    assert_response :success
  end
end
