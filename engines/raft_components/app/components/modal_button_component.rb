#
# Displays a modal dialog when you click the button.
#
# Two usage modes:
#
# (1) Static dialog content
#
#    v.modal_button(title: "Hello") do
#      .modal-body
#        = "World"
#      .modal-
#
# (2) Dynamic dialog content
#
#    v.modal_button(title: "Hello", frame_url: path_to_load_turbo_frame)
#
# NOTE: The body of the modal dialog is tagged with data-turbo-permanent.
#       Doing this will prevent weird artifacts when new content is morphed
#       and the dialog is still open.
#
#       For example, if the dialog has a form and the controller responds
#       with a redirect, the form text fields will flicker with their old values
#       before the new content is entirely morphed. I don't know why it does
#       that, but data-turbo-permanent prevents the flicker.
#
class ModalButtonComponent < ButtonComponent
  self.button_type = "button"

  TEMPLATE = <<~HAML
    .modal.fade{id: @modal_id, tabindex: "-1", "aria-hidden": "true"}
      .modal-dialog
        .modal-content(data-turbo-permanent)
          - if @frame_url
            %turbo-frame{id: @frame_id, src: @frame_url, loading: "lazy"}
              .modal-header
                - if @title
                  %h5.modal-title= @title
                %button(type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close")
              .modal-body
                .d-flex.align-items-center.justify-content-center(style="height: 4em")
                  .spinner-border(role="status")
                    %span.visually-hidden Loading...
              .modal-footer
                %button.btn.btn-secondary(type="button" data-bs-dismiss="modal")
                  Close
          - else
            - if @title
              .modal-header
                %h5.modal-title= @title
                %button(type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close")
            .modal-body
              = content
  HAML

  def initialize(title: nil, modal_id: nil, frame_url: nil, frame_id: nil, subtitle: nil, **args)
    if title
      @title = title
      args[:label] ||= title
    end
    @modal_id  = modal_id || "modal_#{rand(1_000_000_000)}"
    super(**args)
    if frame_url
      @frame_url = frame_url
      @frame_id  = frame_id || "frame_" + @modal_id
      @params[:frame_id] = @frame_id if @frame_id
      @frame_url = add_params(@frame_url, @params)
    end
  end

  def call
    @html["data-bs-toggle"] = "modal"
    @html["data-bs-target"] = '#'+@modal_id
    @html["data-dialog-frame-id"] = @frame_id if @frame_id
    # ^^ this is not used by bootstrap. It is here so that we can use our custom
    # javascript to quickly find which turbo frame is associated with this button, if needed.
    safe_join([
      render_haml(TEMPLATE),
      button_tag
    ])
  end
end
