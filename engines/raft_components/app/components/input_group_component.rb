##
## Usage:
##
##     - v.input_group do
##       = v.input(...)
##       = v.button(...)
##
class InputGroupComponent < ApplicationComponent
  haml_template <<~HAML
    %div.input-group{style: @html[:style], class: @html[:class]}
      = content
  HAML
end
