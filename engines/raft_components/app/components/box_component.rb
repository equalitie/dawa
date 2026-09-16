#
# Like an alert, but with no close button and defaults to non-colored.
# It also supports with_buttons, which show up on the right side.
#
# For example:
#
#   = v.box do |box|
#     Hello
#     - box.with_buttons do
#       = button_tag
#
# The content & icon are vertically aligned top if there are no buttons,
# and aligned center if there are.
#
# At small display sizes, the buttons are stacked in a column under content,
# and the icon is then vertically aligned top.
#
class BoxComponent < ApplicationComponent
  renders_one :buttons, ->(position = :center, &block) do
    content_tag(:div, class: "flex-shrink-1 btn-toolbar align-self-#{position}", &block)
  end

  renders_one :footer
  renders_one :header
  renders_one :image
  renders_many :list_items

  haml_template <<~HAML
    %div{class: box_classes}
      - if header?
        .card-header= header
      .card-body.d-flex.flex-row.gap-3
        - if @icon
          = icon(icon: @icon, size: @size, html: {class: "plain flex-shrink-0"})
        - elsif image?
          = image
        - if !buttons?
          .alert-body.flex-grow-1.align-self-start{class: @html[:class]}
            = content
        - else
          .alert-body.flex-grow-1.align-self-start.align-self-sm-center
            .d-flex.flex-column.flex-sm-row.align-items-sm-center.gap-3
              .flex-grow-1{class: @html[:class]}
                = content
              .flex-shrink-1.btn-toolbar
                = buttons
      - if list_items?
        %ul.list-group.list-group-flush
          - list_items.each do |item|
            %li.list-group-item
              = item
      - if footer?
        .card-footer.p-3.last-child-mb-0= footer
  HAML

  def initialize(color = "normal", icon: nil, size: "md", **args)
    super(**args)
    @color = color
    @icon = icon
    @size = size
  end

  def box_classes
    "card mb-3 btn-white text-bg-#{@color}"
  end

end
