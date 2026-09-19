#
# Submits the current form or the form id specified with v.submit_button(form: id)
#

class SubmitButtonComponent < ButtonComponent
  self.button_type = 'submit'
  self.hidden_form = false
end
