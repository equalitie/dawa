#
# expand a target element to fill full viewport
#
class ExpanderComponent < ApplicationComponent
  def initialize(**kwargs)
    super
  end

  def call
    v.controller("expander", class: "h-100 w-100", style: "position: relative") do |controller|
      safe_join([
        v.button(
          icon: "fullscreen-exit",
          border: false,
          class: "position-absolute top-0 end-0 d-none",
          style: "padding: 4px 8px",
          html: {"data-action": "click->expander#shrink"},
          data: controller.target("shrink_button")
        ),
        v.button(
          icon: "arrows-fullscreen",
          border: false,
          style: "padding: 4px 8px",
          class: "position-absolute top-0 end-0",
          html: {"data-action": "click->expander#expand"},
          data: controller.target("grow_button")
        ),
        content
      ])
    end
  end
end
