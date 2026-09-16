#
# This is the main controller concern that should be included whenever you want
# authentication and authorization from cookie-based sessions.
#
module Auth
  module SessionAuthentication
    extend ActiveSupport::Concern

    included do
      protect_from_forgery with: :exception

      # filters
      prepend_before_action :check_authentication

      # accessors & helpers
      helper Auth::Engine.helpers
      helper_method :current_user
      helper_method :current_link

      # inheritable class attributes
      class_attribute :authentication_required

      # error rescues
      rescue_from ActionController::InvalidAuthenticityToken, with: :render_csrf_problem
      rescue_from Auth::UnauthenticatedRequest,   with: :render_unauthenticated
      rescue_from Auth::SuspendedRequest,         with: :render_suspended
    end

    class_methods do
      def require_authentication(allowed_user_scope: nil)
        self.authentication_required = true
      end

      def optional_authentication(allowed_user_scope: nil)
        self.authentication_required = false
      end
    end

    protected

    def current_user
      @current_user
    end

    def current_link
      @current_link
    end

    def current_invite
      @current_invite
    end

    #
    # Finds the user in session['user_id'] or session['link_id']
    #
    def load_session
      if @current_user.nil? && session[:user_id]
        @current_user = User.find_by_id(session[:user_id])
        reset_session unless @current_user
      elsif @current_link.nil? && session[:link_id]
        @current_link = Link.find_by_id(session[:link_id])
        @current_user = load_anon_user(@current_link)
        reset_session unless @current_link
      end

      if @current_invite.nil? && session[:invite_id]
        @current_invite = Invite.find_by_id(session[:invite_id])
        if @current_invite.nil?
          reset_session
        else
          @current_invite.secret = session[:invite_secret]
        end
      end

      @session_loaded = true
    end

    #
    # This method is the only way to log in a user.
    #
    # @params preserve [String, Symbol, Array] Specifies key(s) in the session we want to
    #   preserve after log in.
    #
    # @param vault [Hash] decrypted copy of user's vault
    #
    def set_current_user!(user, preserve: nil, vault: nil)
      if may_authenticate?(user)
        vault = vault&.to_h # copy the vault since it will get destroyed when session is reset
        reset_and_preserve_session(preserve)
        @current_user = user
        session[:user_id] = user&.id
        current_vault.set(vault) if vault
      else
        raise Auth::UnauthorizedRequest
      end
    end

    #
    # This method is the only way to log in with a link
    #
    def set_current_link!(link)
      raise ArgumentError if link.is_a?(Invite) # link must NOT be an invite
      preserve = [
        :vault, # preserve the vault, in case multiple links have been loaded.
        :links, # keep the list of loaded link_ids
        :link_display_name, # what the anonymous user wants to be called
        :link_hue, # the anon user's color
        :link_membership_code # unique code used for editors
      ]
      reset_and_preserve_session(preserve)
      session[:link_id] = link.id
      session[:link_membership_code] ||= SecureRandom.alphanumeric(Conf.user_code_length)
      session[:link_display_name] ||= "Anonymous"
      session[:link_hue] ||= rand(36)*10
      session[:links] ||= []
      session[:links] << link.id unless session[:links].include?(link.id)
      @current_user = load_anon_user(link)
      @current_link = link
      current_vault.put(link.workspace, link.secret)
    end

    def set_current_invite!(invite)
      raise ArgumentError unless invite.is_a?(Invite) # link MUST be an invite
      reset_and_preserve_session
      @current_invite = invite
      session[:invite_id] = invite.id
      session[:invite_secret] = invite.secret
    end

    def reset_and_preserve_session(preserve = nil)
      preserve_keys = ([ preserve ].flatten + Auth.preserve_session_keys).compact

      # if there is a join workflow active, then preserve
      # the current invite information
      if session[:invite_id] && session[:invite_secret]
        preserve_keys += [ :invite_id, :invite_secret ]
      end
      old_session = {}
      preserve_keys.each do |key|
        old_session[key] = session[key]
      end

      # important to prevent session fixation!
      reset_session

      # restore session keys
      preserve_keys.each do |key|
        session[key] = old_session[key]
      end
    end

    # may override
    def alert_layout
      'application'
    end

    # may override
    def may_authenticate?(user)
      true
    end

    private

    def check_authentication
      load_session unless @session_loaded
      if self.class.authentication_required?
        if !current_user
          raise Auth::UnauthenticatedRequest
        end
      end
    end

    def load_anon_user(link)
      Anon::User.new(link,
        display_name: session[:link_display_name],
        hue: session[:link_hue],
        code: session[:link_membership_code]
      )
    end

    ##
    ## RENDER ERRORS
    ##

    #
    # When cookies are not set or CSRF token is invalid, or
    # session has expired.
    #
    def render_csrf_problem
      respond_to do |format|
        format.html {
          render layout: alert_layout, template: "auth/errors/csrf"
        }
        format.turbo_stream {
          render turbo_stream: turbo_stream.append("alerts", template: "auth/errors/csrf")
        }
      end
    end

    #
    # NOTE:
    #
    # :unauthorized = 401 (not authenticated, despite what the name implies)
    # :forbidden = 403 (access control problem)
    #
    # see: https://gist.github.com/mlanett/a31c340b132ddefa9cca
    #
    # TODO: better error responses for different content types.
    # e.g. json requests should return json
    #
    def render_unauthenticated(exception = nil)
      if request.method == "GET"
        session[:redirect] = request.fullpath
      end
      respond_to do |format|
        format.html {
          redirect_to helpers.evaluate_route(Auth.login_url)
        }
        format.any {
          # render inline: "authentication required", status: :unauthorized
          head :unauthorized
        }
      end
    end

    def render_unauthorized(exception = nil)
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: turbo_stream.append("alerts", template: "auth/errors/unauthorized")
        }
        format.html {
          render layout: alert_layout, template: "auth/errors/unauthorized", status: :forbidden
        }
        format.any {
          # render inline: "authorization required", status: :forbidden
          head :forbidden
        }
      end
    end

    def render_suspended
      render layout: alert_layout, template: "auth/errors/suspended"
    end
  end
end
