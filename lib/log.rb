#
# A global logging helper
# Uses Rails.logger
#
module Log

  PROJECT_ROOT = Regexp.escape(File.expand_path("..", __dir__)).freeze
  PROJECT_ROOT_PATTERN = Regexp.new("^#{PROJECT_ROOT}/").freeze

  def self.api(*msg)
    self.write(:info, *msg)
  end

  #
  # Logging helper with friendly args and exception handling.
  # The last arg is returned.
  #
  # First arg is level, optionally:
  #
  #    Log.write(:error, "oh no")
  #    => "oh no"
  #
  def self.write(*msgs)
    if msgs.first.is_a?(Symbol)
      level = msgs.shift
    else
      level = :error
    end
    exception_index = msgs.index { |m| m.is_a?(Exception) }
    if exception_index
      exception = msgs.delete_at exception_index
      msgs << exception.to_s
      msgs << exception.backtrace&.grep(PROJECT_ROOT_PATTERN)
    end
    Rails.logger.send(level, msgs.join(" "))
    msgs.last
  end
end
