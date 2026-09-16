module LayoutThemeConcern
  extend ActiveSupport::Concern

  included do
    helper_method :theme
  end

  def theme
    Layout::Theme.instance
  end
end
