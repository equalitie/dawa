require_relative "../test_helper"

class SessionFinderTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "tester")
  end

  def test_find_by_session_id_finds_session
    sid = "2::" + SecureRandom.hex(32)
    Auth::Session.create!(session_id: sid, data: { "user_id" => @user.id })
    found = Auth::Session.find_by_session_id(sid)
    assert found
    assert_equal @user.id, found.data["user_id"]
  end

  def test_find_by_session_id_returns_nil_for_missing
    assert_nil Auth::Session.find_by_session_id("2::" + SecureRandom.hex(32))
  end

  def test_find_by_public_id_finds_session
    public_id = SecureRandom.hex(16)
    private_id = Rack::Session::SessionId.new(public_id).private_id
    Auth::Session.create!(session_id: private_id, data: { "user_id" => @user.id })
    found = Auth::Session.find_by_public_id(public_id)
    assert found
  end

  def test_split_session_id_returns_nil_nil_for_invalid_length
    assert_equal [nil, nil], Auth::Session.split_session_id("too-short")
  end

  def test_split_session_id_returns_nil_nil_for_empty
    assert_equal [nil, nil], Auth::Session.split_session_id("")
  end

  def test_session_cannot_be_created_without_full_private_id
    # Session#initialize calls split_session_id on the session_id
    # which expects 67 chars. Short session_id will fail.
    assert_raises(NoMethodError, ActiveRecord::NotNullViolation) { Auth::Session.create!(session_id: "short", data: {}) }
  end

  def test_split_session_id_available_as_class_method
    result = Auth::Session.send(:split_session_id, "")
    assert_equal [nil, nil], result
  end
end
