#
# see https://icons.getbootstrap.com/
#
require 'bootstrap_icons/bootstrap_icon'
require "bootstrap-icons-helper"

module RaftComponents
  module IconHelper
    def icon(icon_arg = nil, label_arg = nil, **kwargs)
      label_arg ||= kwargs.delete(:label)
      icon = Internal.map(icon_arg || kwargs.delete(:icon))
      return label_arg unless icon.present?
      size = Internal.normalize_size(kwargs.delete(:size))
      Internal.icon_tag(icon, label_arg, size: size, **kwargs)
    end

    module Internal
      extend ActionView::Helpers::TagHelper
      extend BootstrapIconsHelper
      extend ERB::Util

      class CustomIcon < BootstrapIcons::BootstrapIcon
        def find_bootstrap_icon
          icon = RaftComponents::IconDefinitions::ICONS[symbol]
          raise_icon_not_found if icon.nil?
          icon
        end
      end

      # symbolic icon to literal icon map
      MAP = {
        "spinner" => "spin-270-ring",
        "ok" => "check-circle",
        "cancel" => "x-circle",
        "add" => "plus-circle",
        "next" => "arrow-right-circle",
        "prev" => "arrow-left-circle"
        # "next" => "chevron-right",
        # "prev" => "chevron-left"
      }.freeze

      def self.icon_tag(icon, label_arg = nil, label: nil, size: nil, color: nil, plain: false, after: false, html: nil)
        label ||= label_arg
        svg_class = if label.present? && !after
          "with-end-label"
        elsif label.present? && after
          "with-start-label"
        elsif plain
          "plain"
        else
          ""
        end

        if html && html[:class]
          svg_class = [svg_class, html[:class]].join(" ")
        end

        if BootstrapIcons::BOOTSTRAP_ICONS_SYMBOLS[icon]
          str = bootstrap_icon(icon, width: size, height: size, class: svg_class)
        else
          str = self.custom_icon(icon, with: size, height: size, class: svg_class)
        end

        if label
          if after
            str = safe_join([ h(label), str ])
          else
            str = safe_join([ str, h(label) ])
          end
        end

        if color
          str = content_tag(:span, class: "text-#{color}") { str }
        end

        str
      end

      # accept icon sizes as any css unit, or "sm", "md", "lg"
      def self.normalize_size(size)
        size = size.to_s
        if !size.present?
          "1em"
        elsif size == "sm"
          "1em"
        elsif size == "md"
          "2em"
        elsif size == "lg"
          "3em"
        else
          size
        end
      end

      def self.custom_icon(symbol, options = {})
        icon = CustomIcon.new(symbol, options)
        content_tag(:svg, icon.path.html_safe, icon.options)
      end

      def self.map(icon)
        icon = icon.to_s
        MAP[icon] || icon
      end
    end

    private_constant :Internal
  end
end
