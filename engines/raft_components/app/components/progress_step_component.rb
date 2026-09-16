class ProgressStepComponent < ApplicationComponent
  #
  # TODO: add aria-pressed="true"
  #

  attr_accessor :active, :label

  haml_template <<~HAML
    - if @url
      %a.step-button.rounded-circle.btn{class: @button_class, href: @url}
        = icon(icon: @icon, size: 18)
        - if @complete
          %span.p-0.mt-1.border.border-light.position-absolute.top-0.start-100.translate-middle.badge.rounded-pill.bg-success
            = icon(icon: 'check', size: 16)
    - else
      %button.step-button.rounded-circle.btn{type: 'submit', class: @button_class, name: @name}
        = icon(icon: @icon, size: 18)
        - if @complete
          %span.p-0.mt-1.border.border-light.position-absolute.top-0.start-100.translate-middle.badge.rounded-pill.bg-success
            = icon(icon: 'check', size: 16)
  HAML

  def initialize(name:, icon:, label: nil, color: 'dark', complete: false, active: false, url: nil)
    @name = name
    @active = active
    @label = label
    @icon = icon
    @color = color
    @url = url
    @complete = complete
  end

  def before_render
    @button_class = [
      "btn-#{@color}",
      @active ? "step-active" : nil
    ].compact.join(' ')
  end
end
