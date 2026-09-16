#
# This view helper allows one to do:
#
#   = v.button(label: "Push Me")
#
module RaftComponents
  module ViewHelper
    def v
      @component_factory ||= begin
        context = if self.is_a?(ActionView::Base)
          self
        elsif @view
          @view
        elsif self.respond_to?(:view_context)
          self.view_context
        else
          raise ArgumentError, "view context is required"
        end
        RaftComponents::ComponentFactory.new(context)
      end
    end
  end
end
