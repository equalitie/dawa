##
## Usage:
##
##     = v.button_group do
##       = v.button(...)
##       = v.button(...)
##
class ButtonGroupComponent < ApplicationComponent

  def initialize(**args)
    super(**args)
    @html[:class] = (@html[:class] || "") + " btn-group"
    @html[:role] = "group"
  end

  def call
    content_tag(:div, @html) do
      content
    end
  end
end
