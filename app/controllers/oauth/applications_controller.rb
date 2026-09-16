#
# Management for Single Sign-on client applications.
#
# This manages Doorkeeper::Application records, modifying OIDC client applications.
# Replaces doorkeeper/oauth/applications_controller.rb.
#
class Oauth::ApplicationsController < BaseAdminController
  before_action :fetch_application, only: [ :show, :edit, :update, :destroy ]

  def index
    @applications = Doorkeeper::Application.order(:name)
  end

  # not used
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
      redirect_to edit_oauth_application_path(@application),
                  flash: { oauth_application_secret: raw_secret }
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if params[:rotate]
      rotate_client_secret
    elsif @application.update(application_params)
      redirect_to edit_oauth_application_path(@application), notice: t("notice.saved")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @application.destroy!
    redirect_to oauth_applications_path, notice: t("notice.destroyed")
  end

  private

  # Rotate the client secret without changing the uid. Clients must update their stored
  # secret; existing tokens remain valid until their natural expiry/revocation.
  def rotate_client_secret
    @application.renew_secret
    @application.save!
    raw_secret = @application.plaintext_secret
    redirect_to edit_oauth_application_path(@application, tab: "client"),
                flash: { oauth_application_secret: raw_secret }
  end

  def fetch_application
    @application = Doorkeeper::Application.find(params[:id])
  end

  def application_params
    permitted = params.require(:oauth_application).permit(:name, :redirect_uri, :confidential, scopes: [])
    # The form posts scopes as an array (checkboxes). Doorkeeper stores them as a
    # space-separated string; join and remove blanks. Default scopes are always applied by
    # doorkeeper, so they are intentionally not stored here.
    if permitted.key?(:scopes)
      permitted[:scopes] = Array(["openid"] + permitted[:scopes]).reject(&:blank?).join(" ")
    end
    permitted
  end
end
