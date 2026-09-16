module RaftComponents
  AVATAR_SMALL_SIZE = 64
  AVATAR_LARGE_SIZE = 256

  # autoload :ViewHelper,    "raft_components/helpers/view_helper"
  # autoload :AvatarHelper,  "raft_components/helpers/avatar_helper"
  # autoload :ColorHelper,   "raft_components/helpers/color_helper"
  # autoload :HasAvatar,     "raft_components/concerns/has_avatar"
  autoload :IconDefinitions, "raft_components/icon_definitions"
  autoload :BuilderHelper,   "raft_components/builder_helper"
  autoload :ColorUtil,       "raft_components/color_util"
  autoload :AttachmentChangedCallback, "raft_components/attachment_changed_callback"

  def self.small_avatar_options
    { resize_to_fill: [ RaftComponents::AVATAR_SMALL_SIZE, RaftComponents::AVATAR_SMALL_SIZE ] }
  end

  def self.large_avatar_options
    { resize_to_fill: [ RaftComponents::AVATAR_LARGE_SIZE, RaftComponents::AVATAR_LARGE_SIZE ] }
  end

  class Engine < ::Rails::Engine
    config.to_prepare do
      ActiveStorage::Attachment.prepend RaftComponents::AttachmentChangedCallback
    end

    initializer "raft_components.importmap", before: "importmap" do |app|
      app.config.importmap.paths << root.join("config/importmap.rb")
      app.config.importmap.cache_sweepers << root.join("app/javascript")
    end

    initializer "raft_components.paths", before: :set_autoload_paths do |app|
      # app.config.autoload_paths    << File.expand_path("../raft_components/components", __FILE__)
      # app.config.autoload_paths    << File.expand_path("../raft_components/helpers", __FILE__)
      # app.config.autoload_paths    << File.expand_path("../raft_components/concerns", __FILE__)
      # app.config.assets.paths      << File.expand_path("../raft_components/stylesheets", __FILE__)
      # app.config.assets.precompile << "raft/components.scss"
    end

    initializer "raft_components.assets" do |app|
      app.config.assets.paths << root.join("app/javascript")
      # app.config.assets.precompile << "raft/components.scss"
    end

    initializer "raft_components.helper" do
      # ActiveSupport.on_load :action_view do
      #  include RaftComponents::ViewHelper
      #  include RaftComponents::AvatarHelper
      #  include RaftComponents::ColorHelper
      # end

      # ActionView::Base.send :include, RaftComponents::ViewHelper
      # ActionView::Base.send :include, RaftComponents::AvatarHelper
      # ActionView::Base.send :include, RaftComponents::ColorHelper
      ActionView::Helpers::FormBuilder.send :include, RaftComponents::BuilderHelper
    end
  end
end
