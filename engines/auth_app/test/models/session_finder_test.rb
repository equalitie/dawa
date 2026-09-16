require_relative "../test_helper"

class SessionFinderTest < ActiveSupport::TestCase
  # FIXME: test that find_by_session_id returns the session for a valid private session id
  def test_find_by_session_id
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that find_by_public_id converts public id to private id and finds the session
  def test_find_by_public_id
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that split_session_id returns [nil, nil] for invalid session id length
  def test_split_session_id_invalid_length
    skip "Not yet implemented"
    assert true
  end
end
