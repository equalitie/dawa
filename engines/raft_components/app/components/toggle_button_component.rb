#
# A checkbox that looks like a button.
#
# <input type="checkbox" class="btn-check" id="btn-check-4" autocomplete="off">
# <label class="btn" for="btn-check-4">Single toggle</label>
#

class ToggleButtonComponent < ButtonComponent
  def initialize(id: nil, value: nil, checked: nil, type: "checkbox", **args)
    super(**args)
    @type = type
    if @name.nil?
      raise ArgumentError, "name is required for toggle_button"
    end
    @id = generate_id(id)
    @value = value
    if checked.nil?
      @checked = field_value == @value
    else
      @checked = checked
    end
  end

  def call
    safe_join([
      helpers.content_tag(:input,
        "", checked: @checked,
        type: @type, name: field_name, value: @value,
        id: @id, class: "btn-check", autocomplete: "off", data: @data
      ),
      helpers.content_tag(:label, @html.merge(for: @id)) {
        icon(icon: @icon, label: @label)
      }
    ])
  end

  def generate_id(id)
    id || "toggle_button_#{rand(1_000_000_000)}"
  end

  #
  # checkbox must have a name that ends in [] so that the params will be an array of
  # the checked items.
  #
  # For example:
  #
  # <input type="checkbox" name="event[day_of_week][]" id="event_dow" value="0" checked="checked">
  # <input type="checkbox" name="event[day_of_week][]" id="event_dow" value="1" checked="checked">
  #
  # Will generate params: {event: {day_of_week: ["0","1"]}}
  #
  def field_name
    if @type == "checkbox"
      super + "[]"
    else
      super
    end
  end
end
