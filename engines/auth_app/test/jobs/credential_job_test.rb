require_relative "../test_helper"

class CredentialJobTest < ActiveSupport::TestCase
  # FIXME: test that perform deletes inactive credentials older than 24 hours
  def test_deletes_old_inactive_credentials
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that perform does not delete active credentials
  def test_preserves_active_credentials
    skip "Not yet implemented"
    assert true
  end
end
