#
# This is the class responsible for creating instances of
# view components.
#

module RaftComponents
  class ComponentFactory
    attr_reader :context, :builder

    def initialize(context, builder: nil, args: nil)
      @context = context
      @builder = builder
      @args    = args
    end

    #
    # allows you to set default values for named arguments.
    #
    # for example:
    #
    # v.args(name: "default_name") do |a|
    #   = a.button(...)
    #
    def args(**args, &block)
      old_args = @args
      @args = args
      yield self
      @args = old_args
    end

    def method_missing(component_name, *args, **named_args, &block)
      component_class_name = component_name.to_s.camelize + "Component"
      begin
        component_class = component_class_name.constantize
      rescue Exception => exc
        raise ArgumentError, "Failed to load or parse View Component with class `#{component_class_name}`. Exception is #{exc}."
      end
      if @args
        deep_combine(named_args, @args)
      end
      if (component_class.instance_method(:factory=) rescue nil)
        named_args.merge!(factory: self)
      end
      component_instance = component_class.send(:new, *args, **named_args)
      if block
        component_instance.render_in(@context, &block)
      else
        component_instance.render_in(@context)
      end
    end

    private

    #
    # like deep_merge, but combines instead of replaces string or array values
    #
    # * deep_combine({x: [1]}, {x: [2]}) => {x: [1, 2]}
    # * deep_combine({x: "aa"}, {x: "bb"}) => {x: "aa bb"}
    # * modifies hash_a
    # * tie goes to hash_a (e.g. when values are not of the same type)
    #
    def deep_combine(hash_a, hash_b)
      hash_b.each do |key, value_b|
        value_a = hash_a[key]
        if value_a.is_a?(Hash) && value_b.is_a?(Hash)
          deep_combine(value_a, value_b)
        elsif value_a.is_a?(String) && value_b.is_a?(String)
          hash_a[key] = [value_a, value_b].join(" ")
        elsif value_a.is_a?(Array) && value_b.is_a?(Array)
          hash_a[key] = value_a + value_b
        else
          hash_a[key] = value_a.presence || value_b
        end
      end
      hash_a
    end
  end
end
