class UserForm < ApplicationForm
  delegate :model_name, to: :@user
  delegate :to_param, to: :@user
  delegate_missing_to :@user

  attr_reader :user

  def initialize(params)
    @user = params.delete(:user) || User.new
    @params = params
  end

  def create
    User.transaction do
      @user = User.new(@params)
      @user.is_active = false
      @user.is_finalized = false
      @user.save!
      @user.credentials.webauthn.create!
    end
  rescue ActiveRecord::RecordNotUnique, ActiveModel::ValidationError => exc
  ensure
    self.errors.merge! @user.errors if @user
    return self
  end

  def update
    @user.update(@params)
  ensure
    self.errors.merge! @user.errors
    return self
  end

  def finalize_enrollment!(invite_id: nil)
    User.transaction do
      Invite.find_by_id(invite_id)&.consume!(@user) if invite_id
      @user.update(is_active: true, is_finalized: true)
    end
  end

  def persisted?
    @user.persisted?
  end
end
