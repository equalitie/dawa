class InitialsController < ActionController::Base
  def show
    name = params[:name] || "?"
    size = params.fetch(:size, 32).to_i

    avatar = RaftComponents::InitialAvatar.new(name, size: size)

    render body: avatar.to_s, content_type: "image/svg+xml", layout: false
  end
end
