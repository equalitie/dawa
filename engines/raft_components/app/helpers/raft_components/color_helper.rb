module RaftComponents
  module ColorHelper
    HAIR_COLORS = %w[
      e8e1e1
      d6b370
      c93305
      b58143
      a55728
      4a312c
      2c1b18
      00bf0a
      0076c1
      b000cd
      ff46d6
    ].freeze

    def hair_color_choices
      HAIR_COLORS
    end

    def random_hair_color
      HAIR_COLORS[rand(HAIR_COLORS.size)]
    end

    SKIN_COLORS = %w[
      fd9841
      f8d25c
      ffdbb4
      edb98a
      d08b5b
      ae5d29
      614335
      371d11
    ].freeze

    def skin_color_choices
      SKIN_COLORS
    end

    def random_skin_color
      SKIN_COLORS[rand(SKIN_COLORS.size)]
    end

    #
    # color hue is an integer 0..360.
    #
    # for the ui buttons, we bucket the hue wheel into steps.
    #
    # 0 and 360 are the same color, so we exclude the final step
    #
    HUES = [
      0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100,
      110, 150, 170, 180, 190, 200, 210, 220, 230,
      240, 250, 260, 270, 280, 290, 300, 340, 350
      ].freeze

    def hue_choices
      HUES
    end

    def random_hue
      HUES[rand(HUES.size)]
    end

    def hue_to_hex(h, s, l)
      '%02x%02x%02x' % RaftComponents::ColorUtil.rgb_from_hsl(h.to_i/360.0, s/100.0, l/100.0)
    end

    def hue_to_color(h, s, l)
      "hsl(#{h} #{s} #{l})"
    end

    def subtle_color(arg)
      hue_to_color(arg, 40, 90)
    end

    def light_color(arg)
      hue_to_color(arg, 50, 80)
    end

    def mid_color(arg)
      hue_to_color(arg, 60, 70)
    end

    def dark_color(arg)
      hue_to_color(arg, 70, 60)
    end
  end
end
