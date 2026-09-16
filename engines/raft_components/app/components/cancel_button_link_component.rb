#
# A link that looks like a button.
#

class CancelButtonLinkComponent < ButtonComponent
  self.default_label = "components.cancel"
  self.default_icon  = "x-lg"
  self.default_color = "dark"

  def call
    link_tag
  end
end
