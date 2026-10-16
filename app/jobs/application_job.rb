class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  protected

  def renderer
    @renderer ||= ApplicationController.renderer.new(
      https: false,
      http_host: "localhost"
    )
  end

  def stream_message_to(stream_name, message, color = "danger")
    turbo_stream_html = renderer.render(
      inline: %[<%= turbo_stream.append('alerts') { tag.div(message, class: "alert alert-#{color}") } %>],
      locals: { message: message, color: color }
    )
    stream_to(stream_name, content: turbo_stream_html)
  end

  #
  # when the content already encodes the turbo action
  # and target.
  #
  def stream_to(stream_name, content:)
    Turbo::StreamsChannel.broadcast_stream_to(
      stream_name,
      content: content
    )
  end

  def stream_append_to(stream_name, target:, content: nil, partial: nil, locals: nil)
    Turbo::StreamsChannel.broadcast_action_to(
      stream_name,
      action: :append,
      target: target,
      content: content,
      partial: partial,
      locals: locals
    )
  end

  def stream_prepend_to(stream_name, target:, content: nil, partial: nil, locals: nil)
    Turbo::StreamsChannel.broadcast_action_to(
      stream_name,
      action: :prepend,
      target: target,
      content: content,
      partial: partial,
      locals: locals
    )
  end

  def stream_replace_to(stream_name, target:, content: nil, partial: nil, locals: nil)
    Turbo::StreamsChannel.broadcast_action_to(
      stream_name,
      action: :replace,
      target: target,
      content: content,
      partial: partial,
      locals: locals
    )
  end
end
