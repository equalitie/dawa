module Layout
  class Theme < HashWithIndifferentAccess
    class << self
      def instance
        @theme ||= Layout::Theme.new
      end
      def configure
        yield instance
      end
    end

    attr_accessor :stylesheets

    def initialize
      @stylesheets = ["application"]
    end

    #
    # hue is an integer in 0..360
    #
    def set_hue(hue)
      saturation = 60
      self.highlight_black_bg   = hue_to_color(hue, saturation, 40)
      self.highlight_dark_bg    = hue_to_color(hue, saturation, 60)
      self.highlight_bg         = hue_to_color(hue, saturation, 75)
      self.highlight_subtle_bg  = hue_to_color(hue, saturation, 93)

      self.highlight_dark_fg    = hue_to_color(hue, 50, 80)
      self.highlight_fg         = hue_to_color(hue, 70, 20)
      self.highlight_subtle_fg  = hue_to_color(hue, 90, 10)

      self.header_bg      = "var(--highlight-bg)"
      self.header_fg      = "var(--highlight-fg)"
      self.header_icon_bg = "var(--highlight-dark-bg)"
      self.sidebar_active_highlight = "var(--highlight-dark-bg)"
      self.breadcrumb_bg  = "var(--highlight-subtle-bg)"
      self.breadcrumb_fg  = "var(--highlight-subtle-fg)"
    end

    #
    # temporary. eventually, all named variables should
    # be defined with attr_accessor
    #
    def method_missing(method_name, *args)
      method_name = method_name.to_s
      if method_name =~ /\=/
        self[method_name.sub('=','')] = args.first
      else
        fetch(method_name.sub('?',''), nil)
      end
    end

    CSS_VARS = %q[
      highlight_black_bg
      highlight_dark_bg
      highlight_dark_fg
      highlight_bg
      highlight_fg
      highlight_subtle_bg
      highlight_subtle_fg
      header_bg
      header_icon_bg
      header_icon_url
      header_fg
      sidebar_active_highlight
      user_selection_bg
      breadcrumb_bg
      breadcrumb_fg
    ]

    def css_variables
      safe_join([
        ":root {",
        safe_join(css_variable_array, "\n"),
        "}"], "\n"
      )
    end

    def css_variable_array
      self.keys.filter_map { |key|
        if CSS_VARS.include?(key) && self[key]
          css_key = key.gsub('_', '-')
          safe_join([ "--", css_key, ":", css_value(key), ";" ])
        end
      }
    end

    def css_value(key)
      if key.end_with?("_url")
        safe_join(["url(", self[key], ")"])
      else
        self[key]
      end
    end
  end
end

Rails.application.config.to_prepare do
  class Layout::Theme
    include RaftComponents::ColorHelper
    include ActionView::Helpers::OutputSafetyHelper
  end
end
