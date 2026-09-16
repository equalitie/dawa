#
# A button that opens a dropdown menu.
#
# Two modes, either item(&block) or with_item():
#
# = v.dropdown_button do |menu|
#   - menu.item { v.button(label: "item 1", ...) }
#   - menu.with_item(label: "item 2", ...)
#
# When using item(), any button component will work. When using
# with_item(), the button created will be a link or a post button
# (post button is used when there are params specified).
#
class DropdownButtonComponent < ButtonComponent
  self.button_type = "button"

  renders_many :items, ->(label: nil, icon: nil, color: "dark", url: nil, params: nil) do
    if params.nil?
      LinkComponent.new(icon: icon, label: label, url: url, color: color, html: { class: "dropdown-item" })
    else
      PostButtonComponent.new(icon: icon, label: label, url: url, params: params, display: "link", color: color, html: { class: "dropdown-item" })
    end
  end

  #
  # split => show a little split between the label and triangle icon
  # triangle => if false, hide the triangle
  #
  def initialize(split: false, triangle: true, **args)
    super(**args)
    @split = split
    @triangle = triangle
    @items = []
  end

  def item(&block)
    @view_context.v.args(html: { class: "dropdown-item" }) do
      @items.append(@view_context.instance_exec(&block))
    end
  end

  def divider
    @items.append(%(<hr class="dropdown-divider">).html_safe)
  end

  def call
    content
    # ^^ this is required to force viewcomponent to evaluate the block.
    # without this, @items will be empty.
    # I am not sure why this is not needed in tests.
    wrapper_class = @split ? "btn-group" : "dropdown"
    content_tag(:div, class: wrapper_class) do
      dropdown_button_tag + dropdown_menu
    end
  end

  def dropdown_button_tag
    @data["bs-toggle"] = "dropdown"
    @data["bs-popper-config"] = '{"strategy":"fixed"}'
    @html["aria-expanded"] = "false"
    @html["class"] += " dropdown-toggle"
    if @triangle == false
      @html["class"] += " no-triangle"
    end
    button_tag
  end

  def dropdown_menu
    if @items.present? || items?
      combined_items = @items + items
      content_tag(:ul, class: "dropdown-menu") do
        safe_join(combined_items.map { |item|
          content_tag(:li, item)
        })
      end
    else
      content_tag(:div, class: "dropdown-menu") { content }
    end
  end
end
