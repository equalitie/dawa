require_relative "../test_helper"

class UserUsernameTest < ActiveSupport::TestCase
  def setup
    @existing_username = "existing-#{SecureRandom.hex(4)}"
    User.create!(username: @existing_username)
  end

  def test_valid_username_accepted
    assert User.new(username: "john").valid?
  end

  def test_valid_username_with_separators
    assert User.new(username: "john-doe").valid?
    assert User.new(username: "jane_doe").valid?
    assert User.new(username: "a.b.c").valid?
  end

  def test_valid_username_with_numbers
    assert User.new(username: "user123").valid?
  end

  def test_invalid_username_too_short
    assert_not User.new(username: "a").valid?
  end

  def test_invalid_username_starts_with_symbol
    assert_not User.new(username: "-john").valid?
  end

  def test_invalid_username_double_symbols
    assert_not User.new(username: "john--doe").valid?
  end

  def test_forbidden_usernames_rejected
    assert_not User.new(username: "admin").valid?
  end

  def test_forbidden_usernames_homoglyphs_rejected
    assert_not User.new(username: "adm1n").valid?
  end

  def test_username_taken_returns_true
    assert User.send(:username_taken?, @existing_username)
  end

  def test_username_taken_returns_false
    assert_not User.send(:username_taken?, "nonexistent")
  end

  def test_username_downcased_before_create
    user = User.create!(username: "mixedcase")
    assert_equal "mixedcase", user.username
  end

  def test_duplicate_username_rejected
    user = User.new(username: @existing_username)
    assert_not user.valid?
    assert user.errors[:username].present?
  end

  def test_username_valid_class_method
    assert User.send(:username_valid?, "validuser")
    assert_not User.send(:username_valid?, "admin")
  end

  def test_username_allowed_class_method
    assert User.send(:username_allowed?, "okay_user")
    assert_not User.send(:username_allowed?, "admin")
    assert_not User.send(:username_allowed?, "adm1n")
    assert_not User.send(:username_allowed?, "r00t")
  end

  def test_max_username_length
    assert_not User.new(username: "a" * 41).valid?
  end
end
