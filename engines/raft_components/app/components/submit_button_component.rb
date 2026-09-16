#
# Submits the current form.
# If you want to submit a different form, use PostButtonComponent or UpdateButtonComponent
#

class SubmitButtonComponent < ButtonComponent
  self.button_type = 'submit'
  self.hidden_form = false
end
