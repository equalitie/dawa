#
# Include this in a model to add avatar support.
#
# The model must have a JSON field called "data".
#
# There are four attributes associated with the avatar:
#
# * avatar_img -- an activestorage attachment for an image avatar.
# * data["avatar"] -- a hash that defines a dicebear avatar
# * data["avatar_img_cache] -- a hash that caches variant info for
#   both the small and large avatar_img variants under "small" and "large" keys.
#   Set to {} or {"small" => false, "large" => false} to record that no attachment
#   exists, so the avatar helper never needs to query Active Storage directly.
# * data["hue"] -- the background hue to use for this avatar.
#

module RaftComponents
  module HasAvatar
    extend ActiveSupport::Concern

    included do
      store_accessor :data, :avatar, :avatar_img_cache, :hue

      validate :validate_avatar_type

      has_one_attached :avatar_img do |attachable|
        attachable.variant :small, RaftComponents.small_avatar_options
        attachable.variant :large, RaftComponents.large_avatar_options
      end

      #
      # Initialize avatar_img_cache to an empty hash on first load so that
      # any subsequent check during a request knows the cache has been primed
      # (even if no attachment exists), avoiding a query to Active Storage.
      #
      after_initialize :prime_avatar_img_cache, if: :persisted?

      define_method(:avatar) do
        read_store_attribute(:data, :avatar) || {}
      end
    end

    def new_avatar_img=(file)
      # overwrite upload file with resized version
      ImageProcessing::Vips.
        source(file).
        resize_to_fill(*RaftComponents.large_avatar_options[:resize_to_fill]).
        call(destination: file.tempfile.path)
      self.avatar_img = file
      self.avatar_img.filename = ["avatar", File.extname(file.original_filename)].join
    end

    #
    # it is a little expensive to display a list of avatars because
    # for each one it must query to see if there is an attachment, then query the blob,
    # then query the variation.
    #
    # instead, we cache the variant info in the "data" hash.
    # this way, we can create avatar urls for any size without hitting the database.
    #
    def attachment_changed(attachment)
      if attachment.name == "avatar_img"
        if attachment.destroyed?
          self.avatar_img_cache = {}
        elsif attachment.persisted?
          if attachment.blob.workspace_id.nil? && self.respond_to?(:workspace_id)
            attachment.blob.update(workspace_id: self.workspace_id)
          end
          cache = {
            "ex" => attachment.filename.extension,
            "ws" => attachment.blob.workspace_id
          }
          {"sm" => :small, "lg" => :large}.each do |key, variant_name|
            variant = attachment.variant(variant_name)
            cache[key] = {
              "vk" => variant.variation.key,
              "id" => variant.blob.signed_id
            }
          end
          self.avatar_img_cache = cache
        end
        self.save
      end
    end

    private

    def prime_avatar_img_cache
      if read_store_attribute(:data, :avatar_img_cache).nil?
        write_store_attribute(:data, :avatar_img_cache, {})
      end
    end

    #
    # for more validations: https://github.com/igorkasyanchuk/active_storage_validations
    #
    def validate_avatar_type
      # Only validate when a new file is being attached in this request.
      # Check the pending attachment changes (in-memory, no DB query).
      change = attachment_changes["avatar_img"]
      return unless change
      return if change.is_a?(ActiveStorage::Attached::Changes::DeleteOne)
      blob = change.attachable
      return unless blob.respond_to?(:content_type)
      unless blob.content_type.in?(%w[image/jpeg image/png image/gif image/webp])
        errors.add(:avatar_img, "must be a JPG, PNG, GIF, or WebP image")
      end
    end
  end
end
