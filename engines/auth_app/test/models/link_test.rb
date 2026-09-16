require_relative "../test_helper"

class LinkTest < ActiveSupport::TestCase
  # FIXME: test that a pending link is disabled when used_count >= max_uses
  def test_disabled_when_used
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that a link is disabled when expired
  def test_disabled_when_expired
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that disabled_reason returns "used" or "expired"
  def test_disabled_reason
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that to_code generates an encrypted code
  def test_to_code
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that find_by_code decrypts and finds the link
  def test_find_by_code
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that link_key creates a new LinkKey scoped to the expiration date
  def test_link_key_creation
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that grants_access_to? delegates to linkable
  def test_grants_access_to
    skip "Not yet implemented"
    assert true
  end

  # FIXME: test that editable? delegates to linkable
  def test_editable
    skip "Not yet implemented"
    assert true
  end
end
