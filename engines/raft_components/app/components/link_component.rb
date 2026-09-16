#
# this is pretty simple, but sometimes it is useful to have a
# link_to that uses the same API as the button components.
#
# Normally, turbo links will prefetch on a hover and if a turbo stream or turbo frame is in the
# response it will update the DOM immediately instead of waiting for the click.
#
# Here is a discussion of why: https://github.com/hotwired/turbo-rails/issues/599
#
# You can disable prefetching of the link by setting either data-turbo-prefetch=false
# or data-turbo-stream=true. either will work.
#
class LinkComponent < ApplicationComponent
  def initialize(url:, turbo: false, prefetch: true, label: nil, icon: nil, target: nil, underline: :hover, color: nil, **kwargs)
    kwargs[:data] ||= {}

    if turbo
      kwargs[:data]["turbo-stream"] = true
    else
      kwargs[:data]["turbo-frame"] = "_top"
    end

    if prefetch == false
      kwargs[:data]["turbo-prefetch"] = false
    end

    super(**kwargs)
    @url = url
    @label = label
    @icon = icon
    @color = color
    @target = target
    @underline = underline
  end

  def call
    if @icon
      @html[:class] += " icon-link"
    end
    if @color
      @html[:class] += " link-#{@color}"
    end
    if @underline
      if @underline == :hover
        @html[:class] += " link-underline link-offset-2-hover link-underline-opacity-0 link-underline-opacity-75-hover"
      end
      if @label
        @label = content_tag(:span) {@label}
      end
    end
    str = icon(label: @label, icon: @icon)
    content_tag(:a, str, href: @url, data: @data, target: @target, **@html)
  end
end
