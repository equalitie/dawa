class Conf
  class << self

    def method_missing(method, *args)
      raise ArgumentError, "Conf.load not yet called (#{method})" unless @loaded
      get(method.to_s, args.first)
    end

    #
    # get the configuration value. note that `false` is a legitimate value, and
    # if ENV is set it overrides config (but it must be defined in config first).
    #
    def get(variable_name, default=nil)
      if ENV[variable_name.upcase] && @data.key?(variable_name)
        ENV[variable_name.upcase]
      elsif !@data[variable_name].nil?
        @data[variable_name]
      else
        default
      end
    end

    def load(*paths, root: nil)
      @data ||= {}
      @definitions ||= {}
      _load_configs(paths, root)
      _expand_variables()
      unless ENV["SKIP_CONF"] || defined?(::RAKEFILE)
        _enforce_definitions()
      end
      unless @data.any?
        raise StandardError, "ERROR Could not load any configuration in paths #{paths.join(', ')}"
      end
      @loaded = true
    end

    def validate
      _enforce_definitions(false)
    end

    def data
      @data
    end

    #
    # creates a temporary stub for a configuration value.
    # we don't use "stub" as the method name because this
    # is already used by minitest.
    # (also, minitest's stub doesn't work here because it
    #  requires that the method already be defined)
    #
    def tmp(**kwargs, &block)
      original = {}
      kwargs.transform_keys! &:to_s
      kwargs.each do |key, value|
        original[key] = data[key]
        data[key] = value
      end
      yield
      kwargs.each do |key, value|
        data[key] = original[key]
      end
    end

    #
    # returns both required and defined key
    def all_keys
      (@data.keys + _required_variables).sort.uniq
    end

    ##
    ## PRIVATE METHODS
    ##

    private

    def _load_configs(paths, root)
      paths.each do |filepath|
        _resolve_paths(root, filepath).each do |fullpath|
          _load_config(fullpath)
        end
      end
    end

    def _expand_variables
      @data.each do |key, value|
        if value.is_a?(String)
          @data[key] = value.gsub(/\$\{(.+?)\}/) do
            get($1)
          end
        end
      end
    end

    def _required_variables
      @definitions.map {|key, value|
        key if value.split(" ").last == "required"
      }.compact
    end

    def _enforce_definitions(exit_on_error=true)
      @definitions.each do |key, value|
        type, required = value.split(" ")
        config_value = get(key)&.to_s
        if required == "required" && !config_value.present?
          puts "ERROR: setting '#{key}' is required."
          if exit_on_error
            exit 1
          else
            next
          end
        end
        next if !config_value.present?

        # these are very crude regexp, but good enough for this job
        # TODO: maybe support IP addresses?

        regexp = case type
        when "string"
          /.*/
        when "hex"
          /\A[0-9a-f]{64}/
        when "domain"
          # allow local domains, like localhost or postgres.private-network
          # but forbid illegal names, like ones with spaces or that end with "-"
          /\A((?!-)[A-Za-z0-9_-]+(?<!-)\.?)+\z/
        when "url"
          /\Ahttps?:\/\/((?!-)[A-Za-z0-9_-]+(?<!-)\.?)+(:\d+)?(\/.*)?\z/
        when "interval"
          /\A\d+ (seconds?|minutes?|hours?|days?|weeks?|months?|years?)\z/
        when "integer"
          /\A[0-9]+\z/
        else
          puts "ERROR: unknown configuration type '#{type}'"
          exit 1
        end

        unless regexp.match(config_value)
          puts "ERROR: setting '#{key}' value '#{config_value}' does not match type '#{type}'"
          exit 1 if exit_on_error
        end

        if type == "url"
          @data[key] = config_value.gsub(/(:|:80|:443)$/, "")
        elsif type == "integer"
          @data[key] = config_value.to_i
        end
      end
    end

    #
    # returns an array of absolute paths given relative paths,
    # resolved relative to root. If * is in the path, then it is
    # expanded to multiple paths.
    #
    def _resolve_paths(root, path)
      if root
        path = File.expand_path(path, root)
      end
      if path =~ /\*/
        return Dir.glob(path)
      else
        return [path]
      end
    end

    #
    # merge config with contents of filepath, if they exist.
    #
    def _load_config(filepath)
      return unless File.exist?(filepath)
      puts "Loading #{filepath}" unless defined?(::RAKEFILE)
      hash = YAML.load_file(filepath, aliases: true)
      return unless hash
      if hash["variables"]
        @definitions.merge!(hash["variables"])
      end
      if hash["defaults"]
        @data.merge!(hash["defaults"])
      end
      environment = begin
        if defined?(Rails.env)
          Rails.env
        elsif ENV["RAILS_ENV"]
          ENV["RAILS_ENV"]
        else
          puts "No Rails environment is defined."
          exit 1
        end
      end
      @data.merge!(hash[environment])
    rescue Exception => exc
      puts "ERROR parsing configuration file '#{filepath}'."
      puts exc
      puts exc.callstack if exc.respond_to?(:callstack)
      exit 1
    end

  end
end
