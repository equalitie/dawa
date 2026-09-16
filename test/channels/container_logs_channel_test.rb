require_relative "../test_helper"
require "docker_engine_ruby"

class ContainerLogsChannelTest < ActionCable::Channel::TestCase
  def setup
    @user = User.create!(username: "log-test-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
  end

  def test_subscribes_to_the_log_stream
    authorized_connection
    stub_logs([ "a", "b" ]) do
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

  def test_select_new_returns_all_without_cursor
    channel = ContainerLogsChannel.allocate
    lines = [ [ 100.0, "a" ], [ 200.0, "b" ] ]

    assert_equal lines, channel.send(:select_new, lines)
  end

  def test_select_new_filters_strictly_newer_than_cursor
    channel = ContainerLogsChannel.allocate
    channel.instance_variable_set(:@cursor, 200.0)
    lines = [ [ 100.0, "a" ], [ 200.0, "b" ], [ 250.0, "c" ] ]

    assert_equal [ [ 250.0, "c" ] ], channel.send(:select_new, lines)
  end

  def test_unwrap_docker_stream_strips_framing_headers_and_timestamps
    channel = ContainerLogsChannel.allocate
    stream = StringIO.new(
      frame(1, "2026-08-01T00:00:01Z one") +
      frame(2, "2026-08-01T00:00:02Z two") +
      frame(1, "2026-08-01T00:00:03Z three")
    ).string

    lines = channel.send(:unwrap_docker_stream, stream)
    assert_equal 3, lines.length
    assert_equal [ "one", "two", "three" ], lines.map(&:last)
    # each line carries a distinct, parseable timestamp
    assert_equal 3, lines.map(&:first).compact.uniq.length
  end

  def test_split_timestamp_parses_rfc3339_prefix
    channel = ContainerLogsChannel.allocate

    ts, text = channel.send(:split_timestamp, "2026-08-01T00:00:01Z hello world")
    assert text == "hello world"
    assert ts.present?

    ts2, text2 = channel.send(:split_timestamp, "no timestamp here")
    assert_nil ts2
    assert_equal "no timestamp here", text2
  end

  private

  def authorized_connection
    stub_connection current_user: @user
  end

  # Build one docker log stream frame with a timestamp prefix: [type][0][0][0][len_be4]["TS msg"]
  def frame(type, text)
    header = [ type, 0, 0, 0 ].pack("C4") + [ text.bytesize ].pack("N")
    header + text
  end

  def stub_logs(lines)
    ts = Time.utc(2026, 8, 1)
    body = lines.each_with_index.map { |line, i| frame(1, "#{(ts + i).iso8601} #{line}") }.join
    io = StringIO.new(body)
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
