module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include Auth::SessionAuthenticationCable
  end
end
