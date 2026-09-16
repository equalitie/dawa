#
# the base class for all forms
#
class ApplicationForm
  include ActiveModel::Model
  include ActiveModel::Translation

  def self.human_attribute_name(attribute, options = {})
    # Derive the ActiveRecord model name from the form class name
    # Converts "WorkspaceForm" -> "workspace", "UserProfileForm" -> "user_profile"
    ar_model_name = self.name.sub(/Form$/, '').underscore
    ar_key = "activerecord.attributes.#{ar_model_name}.#{attribute}"

    if I18n.exists?(ar_key, options[:locale])
      I18n.t(ar_key, **options)
    else
      # Fall back to normal activemodel lookup
      super
    end
  end
end
