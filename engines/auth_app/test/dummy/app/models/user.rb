class User < ApplicationRecord
  include Auth::UserAuthenticate
  include Auth::UserSession

  def self.find_by_login(login)
    User.where(username: login).take
  end

  def anon?
    false
  end
end
