#
# for when you want a link that looks like a button.
#
# by default, turbo behaviors are disabled. pass `turbo: true`
# to enable. i might change the default in the future.
#
# if you want a button with a form that uses GET action, see get_button_component.rb
#
class LinkButtonComponent < ButtonComponent
  def initialize(target: nil, turbo: false, **kwargs)
    super
    @turbo = turbo
    if @turbo === false
      @data["turbo-frame"] = "_top"
    end
    @html[:target] = target
  end

  def call
    if @turbo === true || (@turbo == :auto && request.format.turbo_stream?)
      @data["turbo-stream"] = true
      @data["turbo-action"] = "advance"
    end
    link_tag
  end
end
