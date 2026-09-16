class User < ApplicationRecord
  include Auth::UserAuthenticate
  include Auth::UserSession
  include Auth::UserUsername
  include RaftComponents::HasAvatar

  def self.find_by_login(login)
    User.where(username: login).take
  end

  def anon?
    false
  end
end
