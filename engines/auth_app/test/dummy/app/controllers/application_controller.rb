class ApplicationController < ActionController::Base
  include Auth::SessionAuthentication
  include Auth::Authorization

  allow_browser versions: :modern

  def paginate(relation)
    relation
  end
end
