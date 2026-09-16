class Invite < Link
  has_many :users, dependent: :nullify

  def consume!(user)
    if good?
      user.update(invite: self, is_admin: role_admin?)
      self.increment!(:used_count)
    else
      # shouldn't get here, but just in case
      raise ErrorMessage.new("invite #{invite.state}")
    end
  end
end
