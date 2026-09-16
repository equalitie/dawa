module Auth
  class ApplicationController < Auth.base_controller
    def auth_paginate(relation)
      defined?(paginate) ? paginate(relation) : relation
    end
  end
end
