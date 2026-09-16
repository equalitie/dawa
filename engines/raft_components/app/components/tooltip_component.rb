#
# Display a tooltip, as a wrapper around other elements.
# This is mostly used to wrap around disabled buttons, which can't have tooltips.
#
#   = v.tooltip("hey, click me") do
#     ...
#
class TooltipComponent < ApplicationComponent
  #
  # size: sm, md
  #
  def initialize(label, **kwargs)
    super(**kwargs)
    @label = label
    @data["bs-toggle"] = "tooltip"
  end

  def call
    content_tag(:div, class: @html[:class], data: @data, title: @label) do
      content
    end
  end
end
