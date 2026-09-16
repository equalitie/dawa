#
# Creates a button that shows a bootstrap offcanvas.
#
# The offcanvas can be manually shown/hidden with javascript:
#
# const bsOffcanvas = new bootstrap.Offcanvas("#offcanvas-id")
# bsOffcanvas.show();
# bsOffcanvas.hide();
#

class SlideButtonComponent < ButtonComponent
  self.button_type = "button"

  haml_template <<~HAML
    = button_tag
    .offcanvas.offcanvas-start{id: @canvas_id, tabindex: "-1", data: @offcanvas_data}
      .offcanvas-header
        %h5.offcanvas-title= @title
        %button(type="button" class="btn-close" data-bs-dismiss="offcanvas" aria-label="Close")
      .offcanvas-body
        = content
  HAML

  def initialize(title: nil, id: nil, **args)
    throw :deprecated
    super(**args)
    @offcanvas_data = @data
    @data = nil
    @title      = title || @label
    @canvas_id  = id || "canvas_#{rand(1_000_000_000)}"
    @html["data-bs-toggle"] = "offcanvas"
    @html["data-bs-target"] = '#'+@canvas_id
    @offcanvas_data["bs-scroll"] = "true"
    @offcanvas_data["bs-backdrop"] = "true"
  end
end
