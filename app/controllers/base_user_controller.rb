class BaseUserController < ApplicationController
  before_action :permit_current_user!

end
