#
# Renders a text field with a copy button
#
class CopyComponent < ApplicationComponent
  haml_template <<~HAML
    - if @disabled
      .border.rounded.border-light.p-2.text-secondary.text-nowrap.overflow-hidden
        = @text
    - else
      = v.controller("clipboard", success_content: icon("check-circle")) do |c|
        .input-group
          %input.form-control.border-secondary.shrink-1{type: "text", value: @text, data: c.target("source")}
          %button.btn.btn-outline-secondary{type: "button", "data-action": "clipboard#copy", data: c.target("button")}
            = icon("copy")
  HAML

  def initialize(text:, disabled: false, **kwargs)
    super
    @text = text
    @disabled = disabled
  end
end
