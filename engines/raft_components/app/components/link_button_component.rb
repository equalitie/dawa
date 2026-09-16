# - if @disabled
#  %div{class: @btn_classes}
#    = icon(icon: @icon, label: @label)
# - else
#  = link_to(icon(icon: @icon, label: @label), @url, disabled: @disabled, class: @btn_classes)

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
    end
    link_tag
  end
end
