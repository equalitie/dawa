module RaftComponents
  class InitialAvatar
    HUE_WHEEL = 360
    COLORS = 36 # must divide evenly into 360
    SATURATION = "40%"
    LIGHTNESS = "40%"
    LIMIT = 2

    attr_reader :initials, :shape, :size, :font_size, :fill

    def initialize(name, hue: nil, shape: :circle, size: 32)
      @name = name.to_s.strip
      @shape = shape
      @size = size
      @initials = if @name.index(/[_ -]/)
        @name.split(/[_ -]/)[0, LIMIT].map { |s| s[0].upcase }.join
      elsif @name.empty?
        "?"
      else
        @name[0, LIMIT].upcase
      end
      @font_size = @size * 0.65 + @size/16 - (@initials.length * @size/16)
      if hue
        @fill = "hsl(#{hue}, #{SATURATION}, #{LIGHTNESS})"
      else
        @fill = generate_fill_color(name, self.class::COLORS)
      end
    end

    def name
      @name.empty? ? "?" : @name
    end

    def to_s
      svg = [
        "<svg xmlns='http://www.w3.org/2000/svg' width='#{size}' height='#{size}'>",
          shape == :rect ?
            "<rect width='#{size}' height='#{size}' rx='#{size / 32}' ry='#{size / 32}' fill='#{fill}' />"
          :
            "<circle cx='#{size / 2}' cy='#{size / 2}' r='#{size / 2}' fill='#{fill}' />",
          "<text x='50%' y='50%' fill='white' fill-opacity='0.75' dominant-baseline='central' text-anchor='middle' font-weight='bold' style='font-size: #{font_size}px; font-family: Roboto, -apple-system, BlinkMacSystemFont, Oxygen-Sans, Ubuntu, Cantarell, \"Helvetica Neue\", sans-serif; user-select: none;'>",
            "#{initials}",
          "</text>",
        "</svg>"
      ].join

      svg.html_safe rescue svg
    end

    private

    def valid_colors?
      return false unless colors.respond_to?(:to_i)
      return false unless colors > 0
      HUE_WHEEL % colors == 0
    end

    def valid_size?
      return false unless size.respond_to?(:to_i)
      size.to_i > 0
    end

    def generate_fill_color(name, colors)
      return "hsl(0, 0%, 67%)" if @name.empty?

      hue_step = HUE_WHEEL / colors
      char_sum = name.split("").sum do |c|
        # Multiplication makes sure neighboring characters (like A and B) are one hue step apart.
        c.ord * hue_step
      end

      # Spin the wheel!
      hue = char_sum % HUE_WHEEL

      "hsl(#{hue}, #{SATURATION}, #{LIGHTNESS})"
    end

  end
end
