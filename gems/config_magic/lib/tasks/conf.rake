desc "Export and validate configuration for the current environment"
task :conf do
  puts Rails.env.to_s + ":"
  Conf.all_keys.each do |key|
    value = Conf.get(key)
    if value.is_a?(String) && value.encoding == Encoding::BINARY
      value = value.unpack("H*").first
    end
    puts ["  ", key, ': ', value.inspect].join
  end
  puts
  Conf.validate
end
