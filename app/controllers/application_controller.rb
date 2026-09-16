class ApplicationController < ActionController::Base
  include Auth::SessionAuthentication
  include Auth::Authorization

  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
