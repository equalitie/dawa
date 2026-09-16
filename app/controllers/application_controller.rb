class ApplicationController < ActionController::Base
  include Auth::SessionAuthentication
  include Auth::Authorization
  include DecoratorConcern

  require_authentication
  require_authorization

  before_action :permit_admin!

  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  def permit_admin!
    permit! { current_user&.is_admin? }
  end

  include Pagy::Method
  def paginate(relation = nil, mode = :offset, &block)
    if relation.nil? && block_given?
      relation = yield
    end
    @pagy, records = pagy(mode, relation)
    records
  end
end
