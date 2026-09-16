ENV["RAILS_ENV"] = "test"
require "bootstrap-icons-helper"
require "view_component"
require_relative "../test/dummy/config/environment"
require "rails/test_help"

##
## TEST HELPERS
##

class ActionView::TestCase
  def v
    @component_factory ||= begin
      context = ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil)
      context.extend(RaftComponents::ViewHelper)
      RaftComponents::ComponentFactory.new(context)
    end
  end
end
