# Set up gems listed in the engine's own Gemfile. This is the engine's dummy app
# and must always resolve against its own Gemfile, not an inherited one from the
# parent application. A leaked BUNDLE_GEMFILE (e.g. running `rake test` from a shell
# where the parent app's bundler is active) would otherwise make bundler re-resolve
# and rewrite the PARENT application's Gemfile.lock.
ENV["BUNDLE_GEMFILE"] = File.expand_path("../../../Gemfile", __dir__)

require "bundler/setup" if File.exist?(ENV["BUNDLE_GEMFILE"])
$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)
