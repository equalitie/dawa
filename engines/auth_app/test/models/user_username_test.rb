require_relative "../test_helper"

class UserUsernameTest < ActiveSupport::TestCase
  # FIXME: test that username_valid? accepts valid usernames (alphanumeric with separators)
  def test_valid_username_accepted
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that username_valid? rejects invalid usernames (too short, starts with number)
  def test_invalid_username_rejected
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that username_allowed? rejects forbidden usernames and homoglyphs
  def test_forbidden_usernames
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that username_taken? returns true when username exists
  def test_username_taken
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that usernames are downcased before create
  def test_username_downcased
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that duplicate usernames raise validation error
  def test_duplicate_username_rejected
    skip "Not yet implemented"
    assert true
  end
end
