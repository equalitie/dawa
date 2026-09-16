require_relative "../test_helper"

class SessionJobTest < ActiveSupport::TestCase
  # FIXME: test that perform deletes sessions past the idle timeout and max lifetime
  def test_deletes_expired_sessions
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that words_to_time raises ArgumentError for invalid time strings
  def test_words_to_time_invalid
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that words_to_time correctly parses "X hours" etc
  def test_words_to_time
    skip "Not yet implemented"
    assert true
  end
end
