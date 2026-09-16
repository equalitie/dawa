#
#
# tabs will automatically select if params[:tab] == value
#
# value defaults to "tab-#{label.parameterize}" if not set.
#
class TabComponent < ApplicationComponent
  attr_accessor :tab_id # used by parent

  #
  # default -- this tab should be active by default
  #
  def initialize(active: nil, label: nil, url: nil, value: nil, default: nil, **args)
    super(**args)
    @active = active
    @label = label
    @url = url
    @value = value
    @default = !!default
  end

  def active?
    @active
  end

  def pane_class
    if @active
      "show active"
    else
      ""
    end
  end

  def call
    if parent&.javascript
      render_javascript_tab
    else
      render_tab
    end
  end

  def before_render
    super
    self.tab_id = "tab-#{@label.parameterize}"
    @value ||= self.tab_id
    @active ||= @default || params[:tab] == @value
    @active = !!@active
  end

  def render_tab
    content_tag(:li, class: "nav-item") {
      if @active
        content_tag(:a, class: "nav-link active", "aria-current": "page", href: @url) {
          @label
        }
      else
        content_tag(:a, class: "nav-link", href: @url) {
          @label
        }
      end
    }
  end

  def render_javascript_tab
    link_class = [ "nav-link", (@active ? "active" : nil) ].join(" ")
    content_tag(:button,
      type: "button",
      role: "tab",
      class: link_class,
      "aria-controls": tab_id,
      "aria-selected": @active.inspect,
      data: {
        "bs-toggle": "tab",
        "bs-target": "#"+tab_id,
        "tab-value": @value
      }
    ) do
      @label
    end
  end
end
