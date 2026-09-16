require_relative "../test_helper"

class AttemptTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester")
  end

  # FIXME: test that a successful attempt returns encrypted_data via the data method
  def test_data_returns_encrypted_for_success
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that a failed attempt returns cleartext_data via the data method
  def test_data_returns_cleartext_for_failure
    skip "Not yet implemented"
    assert true
  end
end
