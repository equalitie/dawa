if Conf.demo && !defined?(::RAKEFILE)
  Rails.application.config.after_initialize do
    Dawa::Demo.seed
  end
end
