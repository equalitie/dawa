module Auth
  module ApplicationHelper
    def logout_button
      render 'auth/sessions/logout_button'
    end

    #
    # resolves a string configuration for a url
    # into the actual url.
    #
    # for example:
    #
    #    evaluate_route("auth.new_session_url") => "/auth/sessions/new"
    #
    def evaluate_route(route_helper_str)
      route_helper_str.split(".").inject(self) { |obj, str| obj.send(str) }
    end

    def auth_breadcrumbs(*args, &block)
      defined?(breadcrumbs) ? breadcrumbs(*args, &block) : nil
    end
  end
end
