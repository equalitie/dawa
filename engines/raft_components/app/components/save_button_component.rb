#
# Submits the current form.
# If you want to submit a different form, use PostButtonComponent or UpdateButtonComponent
#

class SaveButtonComponent < SubmitButtonComponent
  self.default_icon = "save"

  def call
    if @label.nil?
      if builder&.object_name
        @label = t("components.save_thing", thing: builder.object_name.capitalize)
      else
        @label = t("components.save")
      end
    end
    super
  end
end
