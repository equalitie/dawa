module Auth
  class ApplicationController < Auth.base_controller
    def auth_paginate(relation)
      defined?(paginate) ? paginate(relation) : relation
    end

    def auth_breadcrumbs(*args, &block)
      defined?(breadcrumbs) ? breadcrumbs(*args, &block) : nil
    end
    helper_method :auth_breadcrumbs
  end
end
