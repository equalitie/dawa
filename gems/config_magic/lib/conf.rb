require_relative "conf/class_methods"

class Conf
  if defined?(Rails::Railtie)
    class Railtie < Rails::Railtie
      rake_tasks do
        load "tasks/conf.rake"
      end
    end
  end
end
