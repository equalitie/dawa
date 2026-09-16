class ApplicationController < ActionController::Base
  include Auth::SessionAuthentication
  include Auth::Authorization
  include ErrorsConcern

  require_authentication
  require_authorization
  before_action :ensure_active

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

  protected

  def ensure_active
    if current_user
      if !current_user.is_active?
        error_message!("Account is not active")
      elsif !current_user.is_finalized?
        redirect_to step_enroll_path(step: "name")
      end
    end
  end
end
