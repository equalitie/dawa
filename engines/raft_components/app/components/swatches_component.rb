#
# creates a set of radio buttons that appear as little clickable color or image swatches
#
# = v.swatches("user[hair_color]") do |swatches|
#   - swatches.with_color('f00')
#   - swatches.with_color('0f0')
#   - swatches.with_color('00f')
#
# Creates:
#
# <div class="radio-swatches">
#   <label>
#     <input type="radio" name="hair_color" value="f00" />
#     <span class="swatch" style="background-color: #f00" />
#   </label
#   <label>
#     <input type="radio" name="hair_color" value="0f0" />
#     <span class="swatch" style="background-color: #0f0" />
#   </label
#   <label>
#     <input type="radio" name="hair_color" value="00f" />
#     <span class="swatch" style="background-color: #00f" />
#   </label
# </div>
#

class SwatchesComponent < ApplicationComponent
  def initialize(name, value: nil, rows: nil, gap: 1, url: nil, size: 24, **args)
    super(**args)
    @name = name
    @value = value
    @size = size # pixels
    @gap = gap   # pixels
    @url = url
    @rows = rows
  end

  renders_many :colors, ->(value = nil, **kwargs) do
    value = kwargs[:value]&.to_s || value&.to_s
    if kwargs[:h]
      color = "hsl(%s %s %s)" % kwargs.slice(:h, :s, :l).values
    elsif kwargs[:r]
      color = "rgb(%s %s %s)" % kwargs.slice(:r, :g, :b).values
    else
      color = "#" + value
    end
    checked = field_value == value
    content_tag(:label, class: "flex-fill") {
      safe_join([
        content_tag(:input, "",
          class: "d-none",
          type: "radio",
          name: field_name,
          value: value,
          checked: checked,
          data: @html[:data]
        ), content_tag(:span, " ",
          class: "w-100 d-block swatch",
          style: "height: #{@size}px; cursor: pointer; background-color: %s" % color
        )
      ])
    }
    end

  renders_many :images, ->(image_url, value:) do
    if @url
      render_image_swatch_as_link(image_url: image_url, value: value)
    else
      render_image_swatch_as_button(image_url: image_url, value: value)
    end
  end

  def render_image_swatch_as_link(value:, image_url:)
    # checked = field_value == value.to_s
    # content_tag(:a) # TODO
  end

  def render_image_swatch_as_button(value:, image_url:)
    checked = field_value == value.to_s
    content_tag(:label) {
      safe_join([
        content_tag(:input, "",
          class: "d-none",
          type: "radio",
          name: field_name,
          value: value,
          checked: checked
        ), content_tag(:span, "",
          class: "d-block swatch",
          style: safe_join([
            "background-image: url(", image_url, "); ",
            "height: ", @size, "px; ",
            "width: ", @size, "px"
          ])
        )
      ])
    }
  end

  def call
    style = @gap ? "gap: #{@gap}px; " : ""
    if @rows
      padding = @gap
      height = ((@rows * (@size + @gap)) - @gap) + padding*2
      style += "height: #{height}px; overflow-y: hidden;"
    else
      padding = 10
    end
    style += "padding: #{padding}px;"
      # content_tag(:div, class: "border rounded p-3") do
      content_tag(:div, class: "border rounded radio-swatches d-flex flex-wrap", style: style) do
        if colors.any?
          safe_join(colors)
        elsif images.any?
          safe_join(images)
        end
      end
    # end
  end
end
