#
# A submit button that can appear inside a form, but which calls
# a separate create form.
#
# works kind of like the rails helper button_to in that it creates its own form.
#

class CreateButtonComponent < ButtonComponent
  self.default_label = "components.create"
  self.default_icon  = "plus-lg"
  self.default_color = "dark"
  self.button_type  = "submit"
  self.hidden_form  = true
end
