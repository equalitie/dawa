#
# This component displays an image "contained" within its parent.
# The image will resize to fit, not grow larger, and maintain its
# aspect ratio.
#
# If the image is not loaded yet, the pixel or placeholder is used.
# The image may have an optional link.
#
# arguments
#   height:       (Integer)
#   width:        (Integer)
#   src:          (String|nil)  URL of the real image
#   alt:          (String)      alt text
#   href:         (String|nil)  optional link
#   pixel:        (String|nil)  1px PNG URL or hex color, e.g. "#a3b2c1"
#   text:         (String)      text when image is absent
#
class ContainImageComponent < ApplicationComponent
  def initialize(height:, width:, src: nil, alt: nil, text: nil, href: nil, pixel: nil, **kwargs)
    super
    @src = src
    @alt = alt
    @text = text
    @href = href
    @width = width.to_f
    @height = height.to_f
    @aspect_ratio = (@width / @height).round(4)
    @style = "--aspect-ratio: #{@aspect_ratio}"
    @box_style = "max-width: #{@width}px; max-height: #{@height}px"
    if pixel
      @pixel_style = pixel.start_with?("#") ? "background-color:#{pixel}" : "background-image:url('#{pixel}')"
    end

    @data["controller"] = "contain-image"
    @data["contain-image-src-value"] = @src
    @data["contain-image-href-value"] = @href
    @data["contain-image-text-value"] = @text
  end

  haml_template <<~HAML
    .contain-image{ class: @html[:class], data: @data, style: @style }
      .contain-image-inner
        .contain-image-box{ style: @box_style }
          - if @pixel_style
            .contain-image-pixel{ data: { "contain-image-target" => "pixel" }, style: @pixel_style }
          - if @src
            %img.contain-image-img{ src: "", alt: @alt, data: { "contain-image-target" => "img" } }
          - if @text
            .contain-image-placeholder{ data: { "contain-image-target" => "placeholder" } }
              = @text
          - if @href
            %a.contain-image-link{ href: @href, data: { "contain-image-target" => "link" } }
  HAML

end
