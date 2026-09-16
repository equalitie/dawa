require_relative "../test_helper"

class AnonymousControllerTest < ActionDispatch::IntegrationTest
  def setup
    User.create!(username: "anon")
  end

  # FIXME: test GET edit requires authentication (anonymous user must be logged in)
  def test_edit_requires_authentication
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test PUT update sets display_name and hue in session
  def test_update
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test PUT update with blank name falls back to default anonymous name
  def test_update_blank_name
    skip "Not yet implemented"
    assert true
  end
end
