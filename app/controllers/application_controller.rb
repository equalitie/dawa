class ApplicationController < ActionController::Base
  include Auth::SessionAuthentication
  include Auth::Authorization
  include ErrorsConcern

  require_authentication
  require_authorization

  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  include Pagy::Method
  def paginate(relation = nil, mode = :offset, &block)
    if relation.nil? && block_given?
      relation = yield
    end
    @pagy, records = pagy(mode, relation)
    records
  end

end
