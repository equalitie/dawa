#
# display a horizontal row, aligned middle, with a standard gap.
#
# = v.flex_bar do |bar|
#   - bar.shrink do
#     = "small"
#   - bar.grow do
#     = "big"
#   - bar.item do
#     = "default"
#
class FlexBarComponent < ApplicationComponent
  renders_many :items, "FlexBarItemComponent"

  def shrink(**args, &block)
    with_item(:shrink, **args, &block)
  end

  def grow(**args, &block)
    with_item(:grow, **args, &block)
  end

  def item(**args, &block)
    with_item(nil, **args, &block)
  end

  def call
    css_class = "d-flex align-items-center mb-3 gap-2 " + @html[:class]
    content_tag(:div, class: css_class, data: @data) do
      safe_join(items)
    end
  end

  class FlexBarItemComponent < ViewComponent::Base
    def initialize(spacing = nil, **args)
      @spacing = spacing
      justify = args.delete(:justify)
      @html = args
      @html[:class] ||= ""
      if justify.to_s == "start"
        @html[:class] += " text-start"
      elsif justify.to_s == "end"
        @html[:class] += " text-end"
      end
    end

    def call
      html_class = @html[:class]
      if @spacing == :grow
        content_tag(:div, content, class: "flex-grow-1 #{html_class}")
      elsif @spacing == :shrink
        content_tag(:div, content, class: "flex-shrink-1 #{html_class}")
      else
        content_tag(:div, content, class: html_class)
      end
    end
  end
end
