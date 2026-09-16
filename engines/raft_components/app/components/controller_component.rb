#
# creates an element for a stimulus controller context.
#
# example:
#
#    = v.controller("my-controller",, value_one: "x", value_two: "y") do |c|
#      = content_tag(:span, "", data: c.target(:my_target))
#      = content_tag(:span, "", {class: "hover"}.merge(c.data_target(:my_target)))
#
# Names for controllers, targets, and values can be specified in any
# case (camel case, dashes, underscores).
#

class ControllerComponent < ViewComponent::Base
  def initialize(stimulus_controller_name, tag: "div", **kwargs)
    @controller = stimulus_controller_name.to_s.underscore.dasherize
    @tag = tag
    @html_style = kwargs.delete(:style)
    @html_class = kwargs.delete(:class)
    @html = kwargs.delete(:html)

    @data = {}
    @data["controller"] = @controller.camelize(:lower)
    if actions = kwargs.delete(:action)
      @data["action"] = parse_actions(actions)
    end
    kwargs.each { |k, v|
      if v.is_a?(Array) || v.is_a?(Hash)
        v = v.to_json
      end
      @data["#{@controller}-#{k.to_s.underscore.dasherize}-value"] = v
    }
  end

  def data_target(target)
    { "data-#{@controller}-target" => target.to_s.camelize(:lower) }
  end

  def target(target)
    { "#{@controller}-target" => target.to_s.camelize(:lower) }
  end

  #
  # Accepts options for passing to the stimulus controller. Supported keys:
  #
  def data(target: nil, action: nil, params: nil, data: {})
    if target
      data["#{@controller}-target"] = target.to_s.camelize(:lower)
    end
    if action
      data["action"] = parse_actions(action)
    end
    if params
      params.each do |key, value|
        param_name = key.to_s.underscore.dasherize
        data["#{@controller}-#{param_name}-param"] = value
      end
    end
    data
  end

  #
  # single quotes are used here for attributes so that json encoded
  # arrays will pass through correctly.
  #
  def call
    attrs = {}
    attrs.merge!(@html) if @html
    attrs["style"] = @html_style if @html_style
    attrs["class"] = @html_class if @html_class
    @data.each do |k, v|
      attrs["data-#{k}"] = v
    end
    tag_str = attrs.map { |k, v|
      escaped_value = v.is_a?(String) ? v&.gsub("'", '"') : v
      %( #{k}='#{escaped_value}')
    }.join
    safe_join([
      %(<#{@tag}#{tag_str}>).html_safe,
      content,
      %(</#{@tag}>).html_safe
    ])
  end

  private

  #
  # adds controller name to action specification(s) if omitted
  #
  def parse_actions(actions)
    actions.split(" ").map { |action|
      if action.index("#")
        action
      else
        # auto insert the controller name when left out
        action.sub("->", "->#{@controller}#")
      end
    }.join(" ")
  end
end
