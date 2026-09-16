#
# A submit button that can appear inside a form, but which calls
# a separate delete form.
#
#
# we could do this:
#   button_tag "Cancel", type: :submit, formmethod: :post, formaction: enroll_cancel_path, name: "_method", value: "delete"
# which is cool and tricky, but breaks rails CSRF because form CSRF token is tied to form method (I think)
#
# Instead, we use a separate hidden form and then use form=formname in the button to
# apply the button to the hidden form.
#

class CancelButtonComponent < DeleteButtonComponent
  self.default_label = "components.cancel"
  self.default_icon  = "x-lg"
  self.default_color = "secondary"
end
