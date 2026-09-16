#
# This concern should be included in any ActionCable::Connection
# that needs authentication via the session.
#
module Auth
  module SessionAuthenticationCable
    extend ActiveSupport::Concern

    included do
      identified_by :current_user
      attr_reader :current_user
      attr_reader :current_vault
      attr_reader :current_link
    end

    def connect
      if request.session["user_id"]
        @current_user = User.find_by_id(request.session["user_id"])
      elsif request.session["link_id"]
        @current_link = Link.find_by_id(request.session["link_id"])
        if current_link
          @current_user = Anon::User.new(
            current_link,
            display_name: request.session["link_display_name"],
            code: request.session["link_membership_code"]
          )
        end
      else
        reject_unauthorized_connection
      end
      @current_vault = Auth::SessionVault.new(request.session)
    end
  end
end
