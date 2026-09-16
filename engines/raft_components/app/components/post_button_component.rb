#
# stand alone update button that includes its own form
#
class PostButtonComponent < ButtonComponent
  self.hidden_form = true
  self.button_type = "submit"

  self.default_method = "post"
  self.default_label = "components.create"
  self.default_icon  = "plus-lg"
  self.default_color = "dark"
end
