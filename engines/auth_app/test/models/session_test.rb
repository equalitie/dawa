require_relative "../test_helper"

class SessionTest < ActiveSupport::TestCase
  def setup
  end

  # session ids must be:
  # "2::" + 64 hex chars
  # see Rack::Session::SessionId
  def id
    "2::" + SecureRandom.hex(32)
  end

  def test_session_cleanup
    Auth::Session.destroy_all

    old  = Auth::Session.create!(session_id: id, created_at: 3.hours.ago)
    idle = Auth::Session.create!(session_id: id, created_at: 1.hour.ago)
    idle.update_column(:updated_at, 4.minutes.ago)
    Auth::Session.create!(session_id: id, created_at: Time.now)

    assert_equal 1, Auth::Session.where("created_at < ?", 2.hours.ago).count
    assert_equal 1, Auth::Session.where("updated_at < ?", 1.minute.ago).count
    assert_equal 3, Auth::Session.count

    Auth.stub(:user_session_idle_timeout, "1 minute") do
      Auth::SessionJob.perform_now
      assert_nil Auth::Session.find_by_session_id(idle.session_id)
    end

    Auth.stub(:user_session_max_lifetime, "2 hours") do
      Auth::SessionJob.perform_now
      assert_nil Auth::Session.find_by_session_id(old.session_id)
    end

    assert_equal 1, Auth::Session.count
  end

end
