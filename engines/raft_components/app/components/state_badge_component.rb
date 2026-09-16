#
# show little badges for a record
#
# it takes a mapping argument that is a hash in the following form:
#
#   state_value => [state_color, state_label]
#
# or
#
#   state_value => [state_color]
#
# or
#
#   state_value => state_color
#
class StateBadgeComponent < ApplicationComponent
  class_attribute :map,   default: {}
  class_attribute :field, default: :state

  def initialize(object = nil, field: nil, map: nil, **args)
    super(**args)
    field_map       = HashWithIndifferentAccess.new(map || self.class.map)
    if object
      object_field    = field || self.class.field
      field_value     = object&.send(object_field)&.to_s
    end
    if field_value && field_map[field_value]
      color_n_label = [ field_map[field_value] ].flatten
      @badge_state_class = "text-bg-" + color_n_label.first
      if color_n_label.length == 1
        @badge_state_label = field_value
      else
        @badge_state_label = color_n_label.last
      end
    else
      @badge_state_label = field_value
      @badge_state_class = "text-bg-dark"
    end
  end

  def call
    if @badge_state_class
      content_tag(:span, class: 'badge rounded-pill ' + @badge_state_class) { t(@badge_state_label) }
    end
  end
end
