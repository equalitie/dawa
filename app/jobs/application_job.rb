class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  protected

  def broadcast_message(stream_name, message, color = "danger")
    turbo_stream_html = renderer.render(
      inline: %[<%= turbo_stream.append('alerts') { tag.div(message, class: "alert alert-#{color}") } %>],
      locals: { message: message, color: "color" }
    )
    turbo_stream_to(stream_name, content: turbo_stream_html)
  end

  #
  # when the content already encodes the turbo action
  # and target.
  #
  def turbo_stream_to(stream_name, content:)
    Turbo::StreamsChannel.broadcast_stream_to(
      stream_name,
      content: content
    )
  end

  def turbo_stream_append_to(stream_name, target:, content:)
    Turbo::StreamsChannel.broadcast_action_to(
      stream_name,
      action: :append,
      target: target,
      content: content
    )
  end

  def turbo_stream_replace_to(stream_name, target:, content:)
    Turbo::StreamsChannel.broadcast_action_to(
      stream_name,
      action: :replace,
      target: target,
      content: content
    )
  end
end
