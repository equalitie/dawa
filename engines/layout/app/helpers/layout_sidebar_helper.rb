module LayoutSidebarHelper
  def sidebar_link(label:, path:, icon: nil, image: nil, active: nil, indent: nil)
    css_class = if active.is_a?(TrueClass)
      "active"
    elsif active.is_a?(Hash)
      self.active(active)
    elsif active == "active"
      "active"
    else
      ""
    end

    if indent
      css_class += " indent-#{indent}"
    end

    graphic = if icon.present?
      icon_class = label.present? ? "with-end-label" : ""
      bootstrap_icon(icon, width: theme.sidebar_icon_size, height: theme.sidebar_icon_size, class: icon_class)
    elsif image
      image
    else
      ""
    end

    label_tag = content_tag(:span, class: 'text') { label }

    link_to(safe_join([ graphic, label_tag ]), path, class: "nav-link #{css_class}", title: label)
  end

  def sidebar_section(label:, icon:)
    content_tag(:div, class: 'section') {
      icon(icon, content_tag(:span, label))
    } + content_tag(:div, '', class: 'section-rule')
  end

end
