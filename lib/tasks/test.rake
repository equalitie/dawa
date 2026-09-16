#
# Rake tasks to help make it easier to deal with putting major application
# components in engines.
#

Dir.chdir(Rails.root) do
  ENGINES_TO_TEST = Dir.glob("{engines,gems}/*")
end

def print_command(command)
  puts ["\033[1;30;106m", command, "\033[0m"].join
end

#
# The goal here is to be able to run tests in engines from the parent
# project. Because we use a shared postgres db for tests we must
# ensure db:test:prepare is run. Also, we must explicitly set
# the Gemfile location to the engine's Gemfile (or it will use the parent's).
#
def run_rake_test(engine)
  print_command("cd #{engine} && RAILS_ENV=test rake test")
  Dir.chdir(engine) do
    # with_unbundled_env strips the parent (root app) bundler's RUBYOPT / BUNDLE_*
    # so the engine's rake test boots against ITS OWN Gemfile.lock, not a leaked
    # root context that would otherwise rewrite a lockfile in the wrong place.
    return Bundler.with_unbundled_env do
      system(
        {
          "RAILS_ENV" => "test",
          "BUNDLE_GEMFILE" => File.expand_path("Gemfile"),
          # Freeze the engine's bundle so its tests can never rewrite or regenerate a
          # Gemfile.lock. This keeps `rake test:all` from polluting any lockfile.
          "BUNDLE_FROZEN" => "true"
        },
        "rake", "test"
      )
    end
  end
end

def run_rails_test(engine)
  command = ["bin/rails", "test", "#{engine}/test"]
  print_command(command.join(" "))
  system(*command)
end

namespace :test do
  desc "Run all engine and gem tests"
  task :all do
    status = true
    Dir.chdir(Rails.root) do
      ENGINES_TO_TEST.each do |engine|
        next unless Dir.exist?("#{engine}/test")
        puts
        if Dir.exist?("#{engine}/test/dummy")
          status = run_rake_test(engine)
        else
          status = run_rails_test(engine)
        end
        puts
      end
    end
    exit(status)
  end
end
