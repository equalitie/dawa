require_relative "../test_helper"

class UserSessionTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester")
  end

  def test_has_many_sessions
    s1 = Auth::Session.create!(session_id: "2::" + SecureRandom.hex(32), data: { "user_id" => @user.id })
    s2 = Auth::Session.create!(session_id: "2::" + SecureRandom.hex(32), data: { "user_id" => @user.id })
    assert_equal [s1, s2], @user.sessions.order(:id)
  end

  def test_sessions_destroyed_on_user_deactivation
    Auth::Session.create!(session_id: "2::" + SecureRandom.hex(32), data: { "user_id" => @user.id })
    assert_equal 1, Auth::Session.where(user_id: @user.id).count

    @user.update!(is_active: false)
    assert_equal 0, Auth::Session.where(user_id: @user.id).count
  end

  def test_sessions_not_destroyed_when_user_stays_active
    Auth::Session.create!(session_id: "2::" + SecureRandom.hex(32), data: { "user_id" => @user.id })
    @user.update!(username: "newname") # other change, not is_active
    assert_equal 1, Auth::Session.where(user_id: @user.id).count
  end
end
