class ApplicationController < ActionController::Base

  allow_browser versions: :modern

  def paginate(relation)
    relation
  end
end
