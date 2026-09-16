require_relative "../test_helper"

class LinkTest < ActiveSupport::TestCase
  def test_disabled_when_used
    link = Link.new(expires_at: 1.week.from_now, max_uses: 10, used_count: 10)
    assert link.disabled?
    assert link.used?
    assert_not link.expired?
    assert_equal "used", link.disabled_reason
    assert_equal "used", link.state
  end

  def test_disabled_when_expired
    link = Link.new(expires_at: 1.day.ago, max_uses: 10)
    assert link.disabled?
    assert link.expired?
    assert_not link.used?
    assert_equal "expired", link.disabled_reason
    assert_equal "expired", link.state
  end

  def test_pending_when_not_used_and_not_expired
    link = Link.new(expires_at: 1.week.from_now, max_uses: 10)
    assert_not link.disabled?
    assert_not link.used?
    assert_not link.expired?
    assert_nil link.disabled_reason
    assert_equal "pending", link.state
  end

  def test_defaults
    link = Link.new(expires_at: 1.week.from_now)
    assert_equal 10, link.max_uses
    assert_equal 0, link.used_count
    assert link.role_none?
  end

  def test_validates_expires_at_presence
    link = Link.new
    assert_not link.valid?
    assert link.errors[:expires_at].present?
  end

  def test_validates_max_uses_range
    link = Link.new(expires_at: 1.week.from_now, max_uses: 0)
    assert_not link.valid?
    link.max_uses = 1000
    assert_not link.valid?
  end

  def test_valid_expires_at_range
    link = Link.new(expires_at: 1.week.from_now, max_uses: 5)
    assert link.valid?
  end

  def test_scopes
    # freeze time so all recorded times match
    travel_to Time.zone.now do
      pending_link = Link.create!(expires_at: 1.day.from_now, max_uses: 10, used_count: 5)
      used_link   = Link.create!(expires_at: 1.day.from_now, max_uses: 10, used_count: 10)
      expired_link = Link.create!(expires_at: 1.day.ago, max_uses: 10)

      assert_equal 1, Link.pending.count
      assert_equal 1, Link.used.count
      assert_equal 1, Link.expired.count
    end
  end

  def test_find_by_code
    link = Link.create!(expires_at: 1.week.from_now)
    assert link.code
    assert_equal 12, link.code.length
    assert_equal link, Link.find_by_code(link.code)
  end
end
