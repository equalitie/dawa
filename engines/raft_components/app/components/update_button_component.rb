#
# stand alone update button that includes its own form
#
class UpdateButtonComponent < ButtonComponent
  self.default_label = "components.update"
  self.default_icon  = "arrow-up-square"
  self.default_method = "put"
  self.button_type  = "submit"
  self.hidden_form  = true
end
