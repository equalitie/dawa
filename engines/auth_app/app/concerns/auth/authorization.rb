#
# Add this concern to a controller to support authorization
#

module Auth
  module Authorization
    extend ActiveSupport::Concern

    included do
      around_action :check_authorization
      prepend_before_action :set_cache_control_header

      attr_accessor :authorized_yet
      class_attribute :authorization_required
      class_attribute :use_around_transaction

      helper_method :permission_denied!

      rescue_from Auth::UnauthorizedRequest,      with: :render_unauthorized
      rescue_from Auth::ForbiddenRequest,         with: :render_unauthorized
    end

    class_methods do
      def require_authorization(rollback: false)
        self.authorization_required = true
        self.use_around_transaction = rollback
      end

      def optional_authorization
        self.authorization_required = false
        self.use_around_transaction = false
      end

      # A shortcut for specifying before_action permissions.
      # For example:
      #
      #   permit_actions!(
      #     view: [:show, :index],
      #     edit: [:edit, :update, :destroy, :new]
      #   ) { @event || @workspace }
      #
      # Is the same as this:
      #
      #   before_action(only: [ :show, :index ])                  { permit_view!(@event || @workspace) }
      #   before_action(only: [ :edit, :update, :destroy, :new ]) { permit_edit!(@event || @workspace) }
      #
      def permit_actions!(**role_map, &block)
        role_map.each do |role, actions|
          before_action(only: actions) { permit_role!(role, &block) }
        end
      end
    end

    protected

    # may override
    def default_authorization
    end

    # manually trigger authorization denied
    def permission_denied!
      raise Auth::ForbiddenRequest
    end

    ##
    ## ALLOWING ACCESS
    ##

    def permit!(&block)
      if block_given?
        passed = yield
      else
        passed = true
      end
      unless passed
        raise Auth::ForbiddenRequest
      end
      self.authorized_yet = true
    end

    def permit_current_user!
      permit! { current_user && !current_user.anon? }
    end

    #
    # This:
    #    permit_role!(:admin) { @object }
    #
    # Is shorthand for
    #    permit! { current_user.may?(:admin, @object) }
    #
    # With some difference:
    #
    # * Immediately raises an exception of the block yields nil
    # * Supports arrays of objects or relations, not just single objects
    #
    def permit_role!(role, &block)
      linkable = instance_exec &block
      if linkable
        permit! {
          if linkable.respond_to?(:all?)
            linkable.all? {|item| current_user.may?(role, item) }
          else
            current_user.may?(role, linkable)
          end
        }
      else
        raise Auth::ForbiddenRequest
      end
    end

    def permit_view!(linkable = @workspace)
      permit! { current_user.may_view?(linkable) }
    end

    def permit_comment!(linkable = @workspace)
      permit! { current_user.may_comment?(linkable) }
    end

    def permit_edit!(linkable = @workspace)
      permit! { current_user.may_edit?(linkable) }
    end

    def permit_admin!(linkable = @workspace)
      permit! { current_user.may_admin?(linkable) }
    end

    ##
    ## PERFORM AUTHORIZATION CHECK
    ##

    #
    # check_authorization is called as an around action.
    #
    # NOTE: This method must never be used with non-text send_stream()
    # responses, because the full blob will still be sent even if the
    # exception is raised.
    #
    def check_authorization
      return if response.redirect?
      check_authentication unless @current_user

      if self.class.authorization_required?
        self.authorized_yet = false
        if self.class.use_around_transaction?
          ActiveRecord::Base.transaction do
            yield
          end
        else
          yield
        end

        permission_denied! unless text_response?

        if !self.authorized_yet
          begin
            default_authorization
          rescue Auth::UnauthorizedRequest, Auth::ForbiddenRequest
            self.authorized_yet = false
          end
        end

        if !self.authorized_yet
          # we have the dreaded double render problem. the scenario is this: the
          # page has already been rendered, but we have just discovered that
          # permit!() was never called. what do do? rails does not officially
          # support throwing out the response and creating a new one.
          # this hacky code works for now, but beware.
          self.response_body = nil
          @_response_body = nil
          raise Auth::ForbiddenRequest
        end
      else
        yield
      end
    end

    private

    def text_response?
      type = response.content_type&.to_s&.split(";")&.first
      return true if type.nil? # not content type, so assume it is ok?
      first_part = type.split("/").first
      first_part == "text" || type == "application/json"
    end

    #
    # when a controller requires authorization (almost always) we want to
    # aggressively prevent caching.
    #
    # NOTE 'no-cache' doesn't work as you might expect.
    # Only 'no-store' will prevent the browser from caching pages.
    #
    def set_cache_control_header
      response.headers["Cache-Control"] = "max-age=0, private, no-store"
    end

  end
end
