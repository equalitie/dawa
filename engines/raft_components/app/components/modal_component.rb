#
# This displays a modal dialog in response to a turbo-frame request.
# Use RemoteModalButtonComponent to make the request.
#
# The bootstrap_controller.js will show this modal immediately
# when loaded into the DOM.
#
# Example:
#
#     = v.modal("My Title", ...) do |v|
#       Modal Content
#       - v.with_button do
#         = v.post_button(...)
#
# Argument keywords:
#
# * :subtitle -- text added to modal header under title
# * :close_button -- show a close button in title (default true)
# * :show -- open visible (default true)
# * :size -- one of nil, "sm", "md", "lg" (default nil)
# * :fullscreen -- if true, create a fullscreen modal (default false)
# * :scroll -- one of nil, false, true, :local (default true).
#   This determines how the modal should scroll. if :local, then content
#   should contain elements like so:
#   ```haml
#      .modal-body-fixed top content
#      .modal-body-scroll Scrollable area
#      .modal-body-fixed bottom content
#   ```
#
class ModalComponent < ApplicationComponent
  renders_one :buttons

  haml_template <<~HAML
    .modal.modal-open{id: @modal_id, class: @html[:class], data: @data}
      .modal-dialog{class: @dialog_class}
        .modal-content
          .modal-header
            %div
              %h5.modal-title= @title
              - if @subtitle
                = @subtitle
            - if @close_button
              %button(type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close")
          #modal-body.modal-body{class: @body_class}
            = content
          - if @close_button || buttons?
            .modal-footer
              .btn-toolbar
                - if @close_button
                  %button.btn.btn-outline-dark(type="button" data-bs-dismiss="modal")
                    = icon(icon: "x-lg", label: t("components.close"))
                = buttons
  HAML

  def initialize(title = "", subtitle: nil, close_button: true, show: true, size: nil, fullscreen: false, scroll: true, **args)
    super(**args)
    @title        = title
    @subtitle     = subtitle
    @close_button = close_button
    dialog_classes = []
    if scroll
      if scroll.to_s == "local"
        dialog_classes << "modal-dialog-body-scrollable"
        @body_class = "local-scroll-parent"
      else
        dialog_classes << "modal-dialog-scrollable"
      end
    end
    if fullscreen
      dialog_classes << "modal-fullscreen"
    end
    if size
      dialog_classes << "modal-#{size}"
    end
    @dialog_class = dialog_classes.join(" ")
    @modal_id     = "modal_#{rand(1_000_000_000)}"
    if show
      @html[:class] += " auto-open"
      @data["controller"] = "bootstrap"
      @data["bootstrap-target"] = "modal"
    end
    if @close_button == false
      @data["bs-backdrop"] = "static" # prevent modal from closing
    end
  end

  def close_button
    content_tag(:button, class: "btn btn-outline-dark", type: "button", data: {"bs-dismiss" => "modal"}) do
      icon(icon: "x-lg", label: "Close")
    end
  end

end
