class MiniButtonComponent < ApplicationComponent
  haml_template <<~HAML
    = link_to(icon(icon: @icon, label: @label), @url, class: "btn btn-mini " + @fill + @color)
  HAML

  def initialize(url:, label: nil, icon: nil, fill: false, color: 'primary')
    @label = label
    @url = url
    @icon = icon
    @fill = fill ? 'btn-' : 'btn-outline-'
    @color = color.to_s
  end
end
