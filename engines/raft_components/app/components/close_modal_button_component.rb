#
# closes a bootstrap modal dialog
#

class CloseModalButtonComponent < ButtonComponent
    self.default_label = "components.close"
    self.default_icon  = "x-lg"
    self.button_type  = "button"

    def initialize(**kwargs)
      super(**kwargs)
      @data["bs-dismiss"] = "modal"
    end
end
