#
#
# This component is used to show a modal or offcanvas when the link is clicked.
# The actual definition of the modal is generated on the server as a response to the request.
# This is in contrast to the `v.modal_button()` which includes the modal content definition.
#
# For example:
#
#     = v.remote_modal_button(icon: "pencil", url: edit_modal_path)
#
# The response must be in a turbo-frame tag with id "modal-frame":
#
#     = turbo_frame_tag "modal-frame" do
#       .modal.modal-open.fade(tabindex="-1" aria-labelledby="exampleModalLabel")
#          ....
#
# The template must have an empty '<turbo-frame id="modal-frame"></turbo-frame>' somewhere
# not hidden.
#
# We add modal-open to modals that should be rendered visibile immediately (e.g. in response to the click.).
# Sadly, bootstrap doesn't have static markup for "show this model".
#
# This global action (could be in a controller) will then show all the .modal-open
#
#      document.addEventListener("turbo:frame-load", (event) => {
#        [...document.getElementsByClassName("modal modal-open")].forEach((el) => {
#          bootstrap.Modal.getOrCreateInstance(el).show();
#        });
#      });
#
# to show a spinner icon while the request is being loaded, we can take advantage of the
# turbo adds aria-busy to turbo frames that are loading.
#
# In the stylesheet:
#
#      turbo-frame[aria-busy="true"] + .frame-progress > .when-not-busy {
#        display: none !important;
#      }
#      turbo-frame[aria-busy="true"] + .frame-progress > .when-busy {
#        display: block !important;
#      }
#
# Update: actually, aria-busy is not set correctly in some cases (nested turbo-frames). So, instead
# you can use "disabled" attribute which will get set correctly when the form is submitted
# (although this approach doesn't work if you also want to sometimes disable the submit button
# without a little spinner).
#

class RemoteModalButtonComponent < ButtonComponent
  self.hidden_form = true
  self.button_type = "submit"
  self.default_method = "get"

  def initialize(**args)
    super
    @data["turbo-frame"] = "modal-frame"
    @data["turbo-stream"] = "true"
    @spin = true # show spinner while button is disabled
  end
end
