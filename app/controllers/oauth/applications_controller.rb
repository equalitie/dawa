#
# Admin CRUD for Doorkeeper OAuth/OIDC client applications.
#
# Granting a third-party app an OAuth client is a privileged operation (it hands out
# credentials a client uses to act on behalf of users), so this controller is admin-only
# via BaseAdminController (which permits only users with `is_admin?`).
#
# NOTE: we deliberately do NOT reuse Doorkeeper's own /oauth/applications web UI or model.
# We manage Doorkeeper::Application records (the same table) through Dawa's admin shell so
# the whole feature is consistent with the rest of Dawa. The routes are mounted under
# /settings/oauth-applications to avoid colliding with Doorkeeper's /oauth routes.
#
class Oauth::ApplicationsController < BaseAdminController
  # BaseAdminController runs `before_action :permit_admin!` (admin-only via is_admin?),
  # matching the other admin controllers (settings, users).

  before_action :fetch_application, only: [ :show, :edit, :update, :destroy, :rotate ]

  def index
    @applications = Doorkeeper::Application.order(:name)
  end

  def show
  end

  def new
    @application = Doorkeeper::Application.new
  end

  def create
    @application = Doorkeeper::Application.new(application_params)
    if @application.save
      # Secret is stored hashed (hash_application_secrets); the plaintext is only available
      # here, immediately after creation. Copy it out and show it once.
      raw_secret = @application.plaintext_secret
      redirect_to settings_oauth_application_path(@application),
                  notice: t(".created"),
                  flash: { oauth_application_secret: raw_secret }
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @application.update(application_params)
      redirect_to settings_oauth_application_path(@application), notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @application.destroy!
    redirect_to settings_oauth_applications_path, notice: t(".destroyed")
  end

  # Rotate the client secret without changing the uid. Clients must update their stored
  # secret; existing tokens remain valid until their natural expiry/revocation.
  def rotate
    # renew_secret regenerates @raw_secret and writes it to the `secret` attribute, but
    # does not persist; save! commits it. The new plaintext is only available immediately
    # (secrets are stored hashed), so capture and flash it for the admin to copy.
    @application.renew_secret
    @application.save!
    raw_secret = @application.plaintext_secret
    redirect_to settings_oauth_application_path(@application),
                notice: t(".rotated"),
                flash: { oauth_application_secret: raw_secret }
  end

  private

  def fetch_application
    @application = Doorkeeper::Application.find(params[:id])
  end

  def application_params
    params.require(:oauth_application).permit(:name, :redirect_uri, :scopes, :confidential)
  end
end
