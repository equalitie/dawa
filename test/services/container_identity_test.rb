require_relative "../test_helper"

class ContainerIdentityTest < ActiveSupport::TestCase
  test "own_container? matches on the host short-id prefix" do
    # Container hostname defaults to the container's short id, e.g. "30a90ebeffa9".
    assert ContainerIdentity.own_container?("30a90ebeffa9847052e3561d2bce134", self_id: "30a90ebeffa9")
    assert ContainerIdentity.own_container?("30a90ebeffa9", self_id: "30a90ebeffa9")
  end

  test "own_container? is case-insensitive" do
    assert ContainerIdentity.own_container?("abc1234567890", self_id: "AbC123")
  end

  test "own_container? is false for unrelated containers and blanks" do
    assert_not ContainerIdentity.own_container?("deadbeef0000ffff", self_id: "30a90ebeffa9")
    assert_not ContainerIdentity.own_container?("deadbeef0000ffff", self_id: nil)
    assert_not ContainerIdentity.own_container?(nil, self_id: "deadbeef0000")
    assert_not ContainerIdentity.own_container?("", self_id: "deadbeef0000")
  end
end
