#
# Creates a bootstrap offcanvas.
#
# The offcanvas can be manually shown/hidden with javascript:
#
# const bsOffcanvas = new bootstrap.Offcanvas("#offcanvas-id")
# bsOffcanvas.show();
# bsOffcanvas.hide();
#
# The class "offcanvas-open" will trigger javascript
# to show this modal immediately when loaded into the DOM.
#

class OffcanvasComponent < ApplicationComponent
  haml_template <<~HAML
    .offcanvas.offcanvas-start{id: @id, tabindex: "-1", data: @data, class: @html[:class]}
      .offcanvas-header
        %h5.offcanvas-title= @title
        %button(type="button" class="btn-close" data-bs-dismiss="offcanvas" aria-label="Close")
      .offcanvas-body
        = content
  HAML

  def initialize(title, show: true, id: nil, **args)
    super(**args)
    @title = title
    @id  = id || "offcanvas-#{rand(100_000_000)}"
    @data["bs-scroll"] = "true"
    @data["bs-backdrop"] = "true"
    if show
      @html[:class] += " auto-open"
      @data["controller"] = "bootstrap"
      @data["bootstrap-target"] = "offcanvas"
    end
  end
end
