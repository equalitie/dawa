class ContainerLogsChannel < ApplicationCable::Channel
  STREAM_PREFIX = "container_logs:"
  TAIL_LINES = 200
  POLL_INTERVAL = 1.5 # seconds

  periodically :stream_latest, every: POLL_INTERVAL

  def subscribed
    @container_id = params[:id]
    reject unless current_user&.is_admin?

    stream_from "#{STREAM_PREFIX}#{@container_id}"
    @last_sent = nil
    stream_latest # immediate first batch
  end

  def unsubscribed
    stop_all_streams
  end

  private

  #
  # Sends the last TAIL_LINES of log output, then on later ticks only the lines
  # appended since the last broadcast. Runs only while a client is subscribed
  # (the periodic timer stops when the subscription is torn down), so nothing is
  # streamed when nobody is viewing.
  #
  def stream_latest
    lines = fetch_log_lines
    fresh, @last_sent = dedupe(lines, @last_sent)
    broadcast_lines(fresh)
  rescue StandardError => e
    Rails.logger.error "[ContainerLogsChannel] log fetch failed: #{e.class}: #{e.message}"
    # log fetch failed (container gone, socket down); keep the channel quiet
  end

  def fetch_log_lines
    io = docker_client.containers.logs(
      @container_id,
      { stdout: true, stderr: true, tail: TAIL_LINES.to_s }
    )
    # The gem returns a StringIO; use its buffer (io.string) to get the content.
    content = io.respond_to?(:string) ? io.string : io.to_s
    unwrap_docker_stream(content)
  end

  #
  # Docker's logs API returns a multiplexed stream framed with an 8-byte header
  # per chunk: [1 byte stream type][3 bytes pad][4 byte big-endian length]
  # followed by that many bytes of payload. Strip the framing so only the log
  # text remains, normalized to UTF-8.
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
      lines << text unless text.empty?
      pos += 8 + length
    end

    lines
  end

  def dedupe(lines, last_sent)
    return [ lines, lines.last ] if last_sent.nil?
    idx = lines.index(last_sent)
    if idx
      new = lines[(idx + 1)..] || []
      [ new, new.any? ? new.last : last_sent ]
    else
      # previous sent line rolled off the tail window; resend the tail
      [ lines, lines.last ]
    end
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
