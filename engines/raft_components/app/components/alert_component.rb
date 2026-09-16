#
# = v.alert("warning") do
#   You shouldn't do that!
#
#
class AlertComponent < ApplicationComponent
  def initialize(color = "primary", dismiss: true, icon: nil, size: "sm", **args)
    super(**args)
    @color = color&.to_s
    @icon = icon.to_s unless icon.nil?
    @dismiss = dismiss
    @size = size&.to_s
    if @icon.nil?
      if @color == "warning"
        @icon = "exclamation-triangle"
      elsif @color == "danger"
        @icon = "exclamation-octagon"
      elsif @color == "info"
        @icon = "info-circle"
      elsif @color == "success"
        @icon = "check-circle"
      end
    end
  end

  def call
    content_tag(:div, class: alert_classes, role: "alert") do
      flex_row do
        safe_join([
          icon_tag,
          content_tag(:div, content, class: "alert-body align-self-start flex-grow-1"),
          close_button
        ])
      end
    end
  end

  def icon_tag
    return unless @icon.present?
    # plain: remove the margin adjustment
    # flex-shrink-0: don't let the svg shrink (it gets weird otherwise)
    icon(icon: @icon, size: @size, html: {class: "plain align-self-start flex-shrink-0"})
  end

  def flex_row
    gap_class = @size == "sm" ? "gap-2" : "gap-3"
    flex_classes = "d-flex flex-row #{gap_class}"
    content_tag(:div, class: flex_classes) do
      yield
    end
  end

  def alert_classes
    "alert alert-#{@color} #{@html[:class]}"
  end

  def close_button
    if @dismiss
      content_tag(:div, class: "flex-grow-1 align-self-start text-end") do
        '<button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>'.html_safe
      end
    end
  end
end
