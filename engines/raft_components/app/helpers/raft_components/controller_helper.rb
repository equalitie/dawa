module RaftComponents
  module ControllerHelper
    def controller_scope(stimulus_controller_name, **kwargs)
      ControllerScope.new(stimulus_controller_name, **kwargs)
    end

    class ControllerScope
      def initialize(stimulus_controller_name, **kwargs)
        @data = {}
        @controller = stimulus_controller_name.to_s.underscore.dasherize
        if actions = kwargs.delete(:action)
          @data["action"] = parse_actions(actions)
        end
        if targets = kwargs.delete(:target)
          @data.merge!(parse_targets(targets))
        end
        @data.merge!(parse_values(kwargs)) if kwargs.any?
      end

      #
      # Accepts options for passing to the stimulus controller.
      # Supported keys: :target, :action, :params, :values
      #
      def data(target: nil, action: nil, values: nil, params: nil, data: {})
        data = @data.merge(data)
        if target
          data.merge!(parse_targets(target))
        end
        data["action"] = parse_actions(action) if action
        data.merge!(parse_values(values)) if values
        data.merge!(parse_params(params)) if params
        data
      end

      private

      def parse_params(params)
        data = {}
        params.each do |key, value|
          param_name = key.to_s.underscore.dasherize
          data["#{@controller}-#{param_name}-param"] = value
        end
        data
      end

      def parse_values(values)
        data = {}
        values.each do |key, value|
          value_name = key.to_s.underscore.dasherize
          if value.is_a?(Array) || value.is_a?(Hash)
            value = value.to_json
          end
          data["#{@controller}-#{value_name}-value"] = value
        end
        data
      end

      def parse_targets(targets)
        data = {}
        [targets].flatten.each do |target|
          data["#{@controller}-target"] = target.to_s.camelize(:lower)
        end
        data
      end

      #
      # adds controller name to action specification(s) if omitted
      #
      def parse_actions(actions)
        actions = actions.split(" ") if actions.is_a?(String)
        [actions].flatten.map { |action|
          if action.index("#")
            action
          else
            # auto insert the controller name when left out
            action.sub("->", "->#{@controller}#")
          end
        }.join(" ")
      end
    end
  end
end
