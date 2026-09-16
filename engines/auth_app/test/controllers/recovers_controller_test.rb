require_relative "../test_helper"

class RecoversControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(username: "tester")
  end

  # FIXME: test GET show renders the recovery code form
  def test_show
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test POST create with valid recovery code logs the user in
  def test_create_valid
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test POST create with invalid recovery code returns error
  def test_create_invalid
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test POST create is rate-limited to 5 requests per 5 minutes
  def test_create_rate_limited
    skip "Not yet implemented"
    assert true
  end
end
