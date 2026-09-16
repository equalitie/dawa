#
# see: https://github.com/rails/activerecord-session_store
#
# requires the following configuration:
#
#    Rails.application.config.session_store :active_record_store
#    ActionDispatch::Session::ActiveRecordStore.session_class = Auth::Session
#

module Auth
  class Session < ActiveRecord::Base
    singleton_class.prepend(Auth::SessionFinder)
    self.table_name = "sessions"

    attr_accessor :session_key

    belongs_to :user, optional: true
    belongs_to :link, optional: true
    belongs_to :attempt, optional: true, class_name: "Auth::Attempt"

    serialize :data, coder: JSON, default: {}
    before_save :touch_session, :set_nonce, :copy_user_id

    def initialize(args)
      args[:session_id], self.session_key = Auth::Session.split_session_id(args[:session_id])
      super
    end

    #def generate_sid
    #  # Generate a longer, more random session ID.
    #  # SecureRandom.hex(16) is the Rails default; let's make it longer.
    #  SecureRandom.hex(32)
    #end

    private

    #
    # this nonce is used for the content security policy to allow
    # javascript and style elements. the nonce is preserved
    # when the session is reset.
    #
    def set_nonce
      data["nonce"] ||= SecureRandom.alphanumeric(16)
    end

    # don't save a new updated_at value unless the
    # old one is more than a minute old.
    def touch_session
      if updated_at.nil? || updated_at < 1.minute.ago
        self.updated_at = Time.now.utc
      end
    end

    #
    # we use this method to elevate some items in request.session to the session
    # record itself.
    #
    # the problem is that request.session returns just the data field of the
    # session record, not the record itself, since the record only exists
    # because we happen to be storing sessions in the database.
    #
    # called before save. ensure our session records are
    # searchable by user id or link id
    #
    def copy_user_id
      self.user_id ||= data["user_id"]
      self.link_id ||= data["link_id"]
      self.attempt_id ||= data["attempt_id"]
    end
  end
end
