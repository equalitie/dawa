#
#  Creates a bootstrap dropdown menu that works just like a normal HTML
#  select box.
#
#  Example:
#
#      v.dropdown_select.new("user_role",
#        options: {
#          "Administrator" => "admin",
#          "Editor" => "editor",
#          "Viewer" => "viewer"
#        },
#        selected: "editor"
#      )
#
class DropdownSelectComponent < ApplicationComponent
  haml_template <<~HAML
    .dropdown{ class: @wrapper_class, data: { controller: "dropdown-select" } }
      = dropdown_button
      %ul.dropdown-menu{ class: @menu_class, data: { dropdown_select_target: "menu" } }
        - @options.each do |label, value|
          %li
            = radio_button(value, label)
            = radio_label(value, label)
  HAML

  def initialize(name, options:, selected: nil, placeholder: "Select an option",
                 wrapper_class: "", button_class: "", menu_class: "", **kwargs)
    @name = name
    @options = normalize_options(options)
    @selected = selected
    @placeholder = placeholder
    @wrapper_class = wrapper_class
    @button_class = button_class
    @menu_class = menu_class
    super(**kwargs)
  end

  private

  def normalize_options(options)
    case options
    when Hash then options.with_indifferent_access
    when Array then options.to_h.with_indifferent_access
    else {}
    end
  end

  def selected_label
    return nil unless @selected.present?
    @options.key(@selected)
  end

  def dropdown_button
    tag.button(
      class: ["btn", "btn-outline-dark", "dropdown-toggle", @button_class].join(" "),
      type: "button",
      data: {
        bs_toggle: "dropdown",
        dropdown_select_target: "button"
      },
      aria: { expanded: "false" }
    ) {
      selected_label || @placeholder
    }
  end

  def radio_button(value, label)
    radio_button_tag(
      @name,
      value,
      value.to_s == @selected.to_s,
      class: "visually-hidden",
      data: {
        action: "change->dropdown-select#updateButtonText",
        dropdown_select_target: "radio",
        label: label
      }
    )
  end

  def radio_label(value, label)
    label_tag(
      "#{@name}_#{value.to_s.parameterize.underscore}",
      label,
      class: "dropdown-item"
    )
  end

end
