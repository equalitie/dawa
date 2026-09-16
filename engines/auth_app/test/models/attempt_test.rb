require_relative "../test_helper"

class AttemptTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester")
  end

  def test_data_returns_encrypted_for_success
    attempt = Auth::Attempt.create!(is_success: true, user: @user, encrypted_data: { "browser" => "Chrome" }, cleartext_data: { "browser" => "Firefox" })
    assert_equal "Chrome", attempt.data["browser"]
  end

  def test_data_returns_cleartext_for_failure
    attempt = Auth::Attempt.create!(is_success: false, user: @user, encrypted_data: { "browser" => "Chrome" }, cleartext_data: { "browser" => "Firefox" })
    assert_equal "Firefox", attempt.data["browser"]
  end

  def test_belongs_to_user
    attempt = Auth::Attempt.create!(is_success: true, user: @user)
    assert_equal @user, attempt.user
  end
end
