#
# A concern that handles the behavior of user sessions.
#
module Auth
  module UserSession
    extend ActiveSupport::Concern

    included do
      has_many :sessions, class_name: "Auth::Session", dependent: :destroy
      before_save :destroy_session
    end

    private

    #
    # ensure all sessions are destroyed if the user is disabled
    #
    def destroy_session
      if self.is_active_changed? && !self.is_active?
        sessions.destroy_all
      end
    end
  end
end
