class User < ApplicationRecord
  include Auth::UserAuthenticate
  include Auth::UserSession
  include Auth::UserUsername
  include RaftComponents::HasAvatar

  belongs_to :invite, optional: true

  before_validation :assign_uuid, on: :create

  validates :uuid, presence: true, uniqueness: true

  def self.find_by_login(login)
    User.where(username: login).take
  end

  def anon?
    false
  end

  private

  def assign_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
