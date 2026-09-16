require_relative "../test_helper"

class CredentialsControllerTest < ActionDispatch::IntegrationTest

  def setup
    User.create!(username: "crow")
  end

  def test_index
    login_as
    get auth.credentials_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
  end
end
