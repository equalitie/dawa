require_relative "../test_helper"

class UserTest < ActiveSupport::TestCase
  def setup
  end

  def test_create
    user = User.create!(username: "newuser_#{SecureRandom.hex(4)}", is_active: true)
    assert user.persisted?
    assert user.is_active?
  end

  def test_find_by_login
    user = User.create!(username: "newuser_#{SecureRandom.hex(4)}")
    found = User.find_by_login(user.username)
    assert_equal user, found
  end

  def test_anon_predicate
    user = User.create!(username: "newuser_#{SecureRandom.hex(4)}")
    assert_not user.anon?
  end
end
