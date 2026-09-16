#
# display a little avatar for a user or member record
#

# object: an object or hash that responds to avatar, display_name, name
# size: the pixel width and height
# label: if label should be shown
# url: if present, make a link to url
# flex: set to false to disable adding 'flex' class when label is present
# wrap: if false, do not wrap img element.
#
class AvatarComponent < ApplicationComponent
  include RaftComponents::AvatarHelper
  include RaftComponents::ColorHelper

  def initialize(object = nil, size: 48, label: false, url: nil, turbo: true, **args)
    super(**args)
    @show   = !object.nil?
    @avatar = object
    if label
      @label = label_str(label)
    else
      @tooltip = label_str
    end
    @size   = size.to_i
    @url    = url
    @turbo  = turbo
    #@flex   = flex
    #@wrap   = wrap
  end

  def label_str(label = nil)
    if label.is_a?(String)
      label
    elsif @avatar.respond_to?(:username)
      @avatar.username
    elsif @avatar.respond_to?(:name)
      @avatar.name
    elsif @avatar.respond_to?(:display_name)
      @avatar.send(:display_name)
    end
  end

  def call
    return unless @show
    items = []
    if @tooltip
      data = {
        "bs-toggle" => "tooltip",
        "bs-title" => @tooltip
      }
    else
      data = nil
    end
    items << content_tag(:img, "", class: 'avatar', src: avatar_url(@avatar, @size), data: data, alt: 'avatar')
    if @label
      if @url
        if @turbo
          items << link_to(@label, @url, class: 'avatar-label')
        else
          items << link_to(@label, @url, class: 'avatar-label', data: { turbo_frame: "_top" })
        end
      else
        items << content_tag(:span, @label, class: 'avatar-label')
      end
    end
    content_tag(:span, class: "avatar", style: avatar_style) { safe_join(items) }
  end

  def avatar_style
    "--avatar-size: #{@size}px"
  end
end
