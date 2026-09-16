class PutSwitchComponent < ApplicationComponent
  haml_template <<~HAML
    = v.controller("refresh", url: @url, method: @method) do |c|
      .form-check.form-switch
        %input.form-check-input{type: "checkbox",
          style: "cursor: pointer",
          role: "switch",
          id: @id,
          disabled: @disabled,
          checked: @checked,
          data: c.data(target: "checkbox", action: "change->refresh#changed")}
        %label.form-check-label{for: @id, style: "cursor: pointer"}
          = @label
  HAML

  def initialize(label:, checked: false, url: nil, disabled: false, **kwargs)
    super
    @id = "checkbox-#{rand(10000000)}"
    @url = url
    @label = label
    @disabled = disabled
    @checked = checked
    @method = "PUT"
  end
end
