class InvitesController < BaseAdminController
  before_action :fetch_invite, only: [ :show, :edit, :update, :destroy ]

  def index
    @invites = Invite.all.updated_at
    if params[:view].nil?
      @invites = @invites.pending
    elsif params[:view] == "used"
      @invites = @invites.used
    elsif params[:view] == "expired"
      @invites = @invites.expired
    end

    # for the inline new form:
    @invite = Invite.new(max_uses: 1, expires_at: 1.week.from_now)
  end

  def show
  end

  def create
    invite = Invite.create(invite_params)
    if invite.persisted?
      invites = Invite.pending.updated_at
      render turbo_stream: [
        turbo_stream.update("invite-list", partial: "table", locals: {invites: invites})
      ]
    else
      render turbo_stream: [
        turbo_stream.replace("new-invite-form", partial: "new_invite_form", locals: { invite: invite })
      ]
    end
  end

  def edit
  end

  def update
    @invite.update(invite_params)
    if @invite.valid?
      redirect_to invites_url
    else
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    @invite.destroy
    redirect_to invites_path
  end

  protected

  def invite_params
    params.expect(invite: [ :max_uses, :role, :label, :expires_at ])
  end

  def fetch_invite
    @invite = Invite.find_by_code(params[:id])
  end
end
