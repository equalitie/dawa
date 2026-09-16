require_relative "../test_helper"
require "docker_engine_ruby"

class ContainerLogsChannelTest < ActionCable::Channel::TestCase
  def setup
    @user = User.create!(username: "log-test-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
  end

  def test_subscribes_to_the_log_stream
    authorized_connection
    stub_logs(%w[a b]) do
      subscribe id: "c1"
    end

    assert subscription.confirmed?
    assert_has_stream "container_logs:c1"
  end

  def test_rejects_non_admin_user
    user = User.create!(username: "log-user-#{SecureRandom.hex(4)}", is_admin: false, is_active: true)
    stub_connection current_user: user
    stub_logs(%w[a]) do
      subscribe id: "c2"
    end

    assert subscription.rejected?
  end

  def test_dedupe_skips_lines_already_sent
    channel = ContainerLogsChannel.allocate

    new1 = channel.send(:dedupe, %w[a b c], nil)
    assert_equal [ %w[a b c], "c" ], new1

    new2 = channel.send(:dedupe, %w[a b c], "c")
    assert_equal [ [], "c" ], new2

    new3 = channel.send(:dedupe, %w[b c d], "b")
    assert_equal [ [ "c", "d" ], "d" ], new3
  end

  def test_unwrap_docker_stream_strips_framing_headers
    channel = ContainerLogsChannel.allocate
    stream = StringIO.new(
      frame(1, "line one") +
      frame(2, "line two") +
      frame(1, "line three")
    ).string

    lines = channel.send(:unwrap_docker_stream, stream)
    assert_equal [ "line one", "line two", "line three" ], lines
  end

  private

  def authorized_connection
    stub_connection current_user: @user
  end

  # Build one Docker log stream frame: [type][0][0][0][len_be4][payload]
  def frame(type, text)
    header = [ type, 0, 0, 0 ].pack("C4") + [ text.bytesize ].pack("N")
    header + text
  end

  def stub_logs(lines)
    io = StringIO.new(lines.join("\n") + "\n")
    client = Object.new
    client.define_singleton_method(:containers) do
      Object.new.tap do |c|
        c.define_singleton_method(:logs) { |id, **| io }
      end
    end
    ContainerLogsChannel.define_method(:docker_client) { client }
    yield
  ensure
    ContainerLogsChannel.send(:remove_method, :docker_client)
  end
end
