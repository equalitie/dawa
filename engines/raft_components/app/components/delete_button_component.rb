#
# A submit button that can appear inside a form, but which calls
# a separate delete form.
#
# we could do this:
#   button_tag "Cancel", type: :submit, formmethod: :post, formaction: enroll_cancel_path, name: "_method", value: "delete"
# which is cool and tricky, but breaks rails CSRF because form CSRF token is tied to form method (I think)
#
# Instead, we use a separate hidden form and then use form=formname in the button to
# apply the button to the hidden form.
#

class DeleteButtonComponent < ButtonComponent
  self.button_type = "submit"
  self.hidden_form = true

  self.default_method = "delete"
  self.default_label = "components.delete"
  self.default_icon  = "trash"
  self.default_color = "dark"

  def initialize(confirm: nil, **args)
    super(**args)
    if confirm === true
      confirm = "Are you sure?"
    end
    @data["turbo-confirm"] = confirm
  end
end
