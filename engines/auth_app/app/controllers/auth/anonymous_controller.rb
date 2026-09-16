#
# Allow anonymous users to modify aspects of their current anonymous session.
#
module Auth
  class AnonymousController < ApplicationController
    require_authentication
    optional_authorization

    # show edit dialog
    def edit
    end

    def update
      session[:link_display_name] = sane_name(params[:display_name])
      session[:link_hue] = params[:hue].to_i
      redirect_to params[:return_path]
    end

    private

    def sane_name(name)
      if name =~ /[[:word:]]+/
        name.strip.truncate(30)
      else
        t("auth.anonymous_name")
      end
    end
  end
end
