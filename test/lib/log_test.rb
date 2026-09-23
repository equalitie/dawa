require "test_helper"
require "stringio"
require "logger"

#
# Tests for lib/log.rb, the small logging helper

class LogTest < ActiveSupport::TestCase
  ##
  ## write
  ##

  test "write logs the messages joined, at the level named by the first symbol" do
    with_log_io do |io|
      result = Log.write(:info, "hello", "world")

      assert_match(/INFO -- : hello world/, io.string)
      # The documented return value: the last arg, so `write` can wrap an expression without
      # changing it.
      assert_equal "world", result
    end
  end

  test "write defaults to error when the first arg is not a level" do
    with_log_io do |io|
      Log.write("something went wrong")

      assert_match(/ERROR -- : something went wrong/, io.string)
    end
  end

  test "write does not drop a lone message" do
    # A single non-symbol arg is the whole message, not a level. Getting this wrong would log an
    # empty line, which is worse than no line at all.
    with_log_io do |io|
      assert_equal "only", Log.write("only")
      assert_match(/ERROR -- : only/, io.string)
    end
  end

  ##
  ## api
  ##

  test "api logs at info" do
    with_log_io do |io|
      Log.api("->", %({"jsonrpc":"2.0"}))

      assert_match(/INFO -- : -> \{"jsonrpc":"2.0"\}/, io.string)
    end
  end

  test "api returns its last argument" do
    with_log_io do
      assert_equal "last", Log.api("first", "last")
    end
  end

  ##
  ## exceptions
  ##

  test "an exception's to_s appears in the log" do
    # The exception is pulled out of the args and replaced by its backtrace, so without this the
    # log says WHERE the failure happened but never WHAT failed -- the daemon's error text, which
    # is usually the only part that names the cause, was dropped entirely.
    error = exception_with_backtrace(project_frame("app/services/thing.rb", 12))

    with_log_io do |io|
      Log.write(:error, "handler died", error)

      assert_includes io.string, error.to_s
    end
  end

  test "an exception's project backtrace lines are logged" do
    # The helper pulls the Exception out of the args and appends the frames under the project
    # root, so the log says where in Dawa the failure happened.
    error = exception_with_backtrace(
      project_frame("app/services/thing.rb", 12),
      gem_frame("foo-1.0/lib/foo.rb", 3)
    )

    with_log_io do |io|
      Log.write(:error, "kaboom", error)

      assert_match(/app\/services\/thing\.rb/, io.string)
    end
  end

  test "backtrace frames outside the project are left out" do
    # The point of the filter: a gem frame is noise, and the project root is what distinguishes
    # a Dawa bug from a dependency's.
    error = exception_with_backtrace(
      project_frame("app/services/thing.rb", 12),
      gem_frame("foo-1.0/lib/foo.rb", 3)
    )

    with_log_io do |io|
      Log.write(:error, "kaboom", error)

      assert_no_match(/foo-1\.0\/lib\/foo\.rb/, io.string)
    end
  end

  private

  # A real Logger over a StringIO. `Rails.logger` is a genuine singleton method, so it is aliased
  # aside and restored -- never `remove_method`d, which would delete Rails' own method for the
  # rest of the process (the mistake the stub helpers in the controller tests warn about).
  def with_log_io
    io = StringIO.new
    logger = Logger.new(io)

    Rails.singleton_class.alias_method(:logger_without_stub, :logger)
    Rails.define_singleton_method(:logger) { logger }

    yield io
  ensure
    Rails.singleton_class.alias_method(:logger, :logger_without_stub)
    Rails.singleton_class.send(:remove_method, :logger_without_stub)
  end

  def exception_with_backtrace(*frames)
    error = RuntimeError.new("kaboom")
    error.set_backtrace(frames)
    error
  end

  # A frame shaped like a real backtrace entry under the project.
  def project_frame(path, line)
    File.join(Rails.root.to_s, path) + ":#{line}:in 'log_test'"
  end

  # A frame shaped like a real backtrace entry in an installed gem.
  def gem_frame(path, line)
    File.join("/usr/lib/ruby/gems/3.4.0/gems", path) + ":#{line}:in 'call'"
  end
end
