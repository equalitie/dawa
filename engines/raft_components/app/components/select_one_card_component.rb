#
# creates a set of radio buttons that appear as little clickable cards
# with arbitrary content.
#
# = v.select_one_card("profile_id") do |select|
#   - @profiles.each do |profile|
#     - select.with_card(profile.id) do
#       = v.profile(profile)
#

class SelectOneCardComponent < ApplicationComponent

  haml_template <<~HAML
    .row.row-cols-2.row-cols-lg-3.g-3
      - cards.each do |card|
        .col
          = card
  HAML

  def initialize(name, **kwargs)
    @name = name
    super(**kwargs)
  end

  renders_many :cards, ->(value, id: nil, checked: nil, hue: nil, &block) do
    checked ||= field_value.to_s == value.to_s
    radio_id = id || "#{field_name}-#{value}".parameterize
    card_style = if hue
      [
        "--hover-bg: %s" % subtle_color(hue),
        "--border-color: %s" % mid_color(hue),
        "--hover-border-color: %s" % dark_color(hue),
        "--selected-border-color: %s" % mid_color(hue),
        "--selected-bg: %s" % light_color(hue),
      ].join(";")
    end
    safe_join([
      content_tag(:input, "",
        id: radio_id,
        class: "radio-input d-none",
        type: "radio",
        name: field_name,
        value: value,
        checked: checked,
        data: @html[:data]
      ),
      content_tag(:label, class: "card radio-card h-100 p-3 hover", style: card_style, for: radio_id) {
        content_tag(:div, class: "card-body p-0", &block)
      }
    ])
  end

end
