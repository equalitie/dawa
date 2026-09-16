
#
# display an icon with some text hanging off it.
#
#  [ icon ]  text will go here
#            and multiple lines go here.
#
# see https://getbootstrap.com/docs/5.3/utilities/background/
# for list of colors
#
class IconIndentComponent < ApplicationComponent
  haml_template <<~HAML
    .d-flex.justify-content-start.align-items-top.gap-2
      .flex-shrink-0
        .rounded.p-3{class: @color}
          = icon(icon: @icon, size: @size)
      .flex-grow-1
        = content
  HAML

  #
  # size: sm, md, or lg
  #
  def initialize(icon, size: "md", color: "highlight", **args)
    super(**args)
    @icon = icon
    @color = "bg-" + color
    size = size.to_s
    if size == "sm"
      @size = 24
    elsif size == "md"
      @size = 32
    else
      @size = 64
    end
  end
end
