class ContainerLogsChannel < ApplicationCable::Channel
  STREAM_PREFIX = "container_logs:"
  TAIL_LINES = 200
  POLL_INTERVAL = 1.5 # seconds

  periodically :stream_latest, every: POLL_INTERVAL

  def subscribed
    @container_id = params[:id]
    reject unless current_user&.is_admin?

    stream_from "#{STREAM_PREFIX}#{@container_id}"
    @cursor = nil
    stream_latest # initial dump of the tail window
  end

  def unsubscribed
    stop_all_streams
  end

  private

  #
  # On the first tick (usually from #subscribed) dump the last TAIL_LINES of log
  # output. On subsequent ticks fetch only the lines that Docker has appended
  # since the last line we sent, by asking for logs `since` our cursor and then
  # filtering to strictly-newer timestamps. Each line is broadcast exactly once;
  # the only retained state is a small timestamp cursor (there is no growing
  # cache), and polling stops when nobody is subscribed.
  #
  def stream_latest
    lines = fetch_log_lines
    fresh = select_new(lines)
    return if fresh.empty?

    broadcast_lines(fresh.map { |_ts, text| text })
    @cursor = fresh.last.first
  rescue StandardError => e
    Rails.logger.error "[ContainerLogsChannel] log fetch failed: #{e.class}: #{e.message}"
    # log fetch failed (container gone, socket down); keep the channel quiet
  end

  #
  # Fetches logs with timestamps so each line can be tracked by its timestamp.
  # The first call returns the tail window (TAIL_LINES); later calls return only
  # output since the last cursor via the Docker `since` parameter (second
  # precision), with exact sub-second dedup done client-side in #select_new.
  #
  def fetch_log_lines
    params = { stdout: true, stderr: true, timestamps: true }
    if @cursor
      # Only the lines appended since the last one we sent: Docker's `since`
      # (integer seconds) bounds the query, and #select_new drops same-second
      # duplicates client-side. No `tail` cap here so no lines are dropped.
      params[:since] = @cursor.to_i
    else
      # First tick: initial dump of the tail window.
      params[:tail] = TAIL_LINES.to_s
    end

    io = docker_client.containers.logs(@container_id, params)
    # The gem returns a StringIO; use its buffer (io.string) to get the content.
    content = io.respond_to?(:string) ? io.string : io.to_s
    unwrap_docker_stream(content)
  end

  #
  # Docker's logs API returns a multiplexed stream framed with an 8-byte header
  # per chunk: [1 byte stream type][3 bytes pad][4 byte big-endian length]
  # followed by that many bytes of payload. With `timestamps` enabled each
  # payload is prefixed with an RFC3339 timestamp and a space. Returns an array
  # of [timestamp_float_or_nil, text] pairs.
  #
  def unwrap_docker_stream(content)
    return [] if content.nil? || content.empty?

    bytes = content.b
    lines = []
    pos = 0
    size = bytes.bytesize

    while pos + 8 <= size
      length = (bytes.getbyte(pos + 4) << 24) |
               (bytes.getbyte(pos + 5) << 16) |
               (bytes.getbyte(pos + 6) << 8) |
               bytes.getbyte(pos + 7)
      payload = bytes.byteslice(pos + 8, length)
      break if payload.nil?
      text = payload.to_s.force_encoding(Encoding::UTF_8).scrub
      text = text.sub(/\R+\z/, "") # drop trailing newline(s), keep leading whitespace
      pos += 8 + length
      next if text.empty?

      ts, message = split_timestamp(text)
      lines << [ ts, message || text ]
    end

    lines
  end

  #
  # When Docker is asked for timestamps, each line begins with an RFC3339
  # timestamp followed by a space, e.g. "2026-08-01T00:01:28.123456789Z msg".
  # Returns [timestamp_float, remainder]; if there is no leading timestamp,
  # returns [nil, line] and the caller falls back to the full text.
  #
  def split_timestamp(line)
    index = line.index(" ")
    return [ nil, line ] unless index && index < line.length

    ts = line[0...index]
    parsed = Time.parse(ts)
    [ parsed.to_f, line[(index + 1)..] ]
  rescue ArgumentError
    [ nil, line ]
  end

  #
  # Filters [ts, text] pairs to only those newer than @cursor. With a nil cursor
  # (first tick) everything passes. Strictly-newer avoids re-sending lines from
  # the same second that Docker's `since` (integer seconds) may return.
  #
  def select_new(lines)
    return lines unless @cursor
    lines.select { |ts, _| ts && ts > @cursor }
  end

  def broadcast_lines(lines)
    return if lines.empty?
    # Pass the message as an explicit positional hash: Server#broadcast has a
    # `coder:` keyword param, so a bare `lines: lines` would be treated as keyword
    # arguments (yielding an "expected 2, given 1" error).
    ActionCable.server.broadcast "#{STREAM_PREFIX}#{@container_id}", { lines: lines }
  end

  def docker_client
    @docker_client ||= begin
      client_options = {
        max_retries: 2,
        timeout: 10,
        base_url: Conf.docker_url
      }
      DockerEngineRuby::Client.new(**client_options)
    end
  end
end
