module RaftComponents
  module AvatarHelper
    #
    # there are a lot of different ways to specify an avatar:
    #
    # * avatar_img       -- an activestorage atttachment
    # * avatar_img_cache -- cached version of avatar_img
    # * hash             -- a hash that defines avatar fields
    # * name             -- used for initial avatars
    # * hue              -- set the bg color of non-image avatar
    #
    # This method normalizes this information regardless of the argument.
    #
    # priority is given to avatar_img_cache, then avatar_img, and finally avatar.
    #
    # The avatar_img_cache stores either variant entries keyed by "small"/"large"
    # (if an attachment exists) or an empty hash (if no attachment exists, primed
    # by HasAvatar#prime_avatar_img_cache). This allows the helper to return the
    # correct result without ever querying Active Storage for the attachment.
    #
    def normalize_avatar(record, size)
      variant = (size > RaftComponents::AVATAR_SMALL_SIZE/2) ? "lg" : "sm"

      avatar = if record.is_a?(Hash)
        record
      elsif record.respond_to?(:avatar_img_cache) && record.avatar_img_cache.is_a?(Hash) && record.avatar_img_cache.any?
        {
          "cache" => {
            "ex" => record.avatar_img_cache["ex"],
            "ws" => record.avatar_img_cache["ws"],
            "vk" => record.avatar_img_cache.dig(variant, "vk"),
            "id" => record.avatar_img_cache.dig(variant, "id")
          }
        }
      elsif record.respond_to?(:avatar) && record.avatar.is_a?(Hash)
        record.avatar
      else
        {}
      end

      avatar["variant"] = variant
      avatar["hue"] = record&.hue.presence.to_i
      avatar["name"] = record.respond_to?(:name) && record.name.presence ||
                       record.respond_to?(:display_name) && record.display_name.presence ||
                       record.respond_to?(:username) && record.username.presence ||
                       "unknown"

      return avatar
    end

    #
    # generate a URL for an avatar of any type
    #
    def avatar_url(record, size = RaftComponents::AVATAR_SMALL_SIZE)
      avatar = normalize_avatar(record, size)
      if avatar["cache"]
        helper_context.main_app.workspace_send_blob_variant_path(
          avatar["cache"]["ws"],       # workspace id
          avatar["cache"]["id"],       # blob signed id
          avatar["cache"]["vk"],       # variant key
          "avatar.#{avatar["cache"]['ex']}" # filename
        )
      elsif avatar["seed"]
        dicebear_url(**avatar.slice("radius", "seed", "hair_color", "skin_color", "mouth", "hue", "bg_color").symbolize_keys)
      else
        initials_url(name: avatar["name"], hue: avatar["hue"])
      end
    end

    def avatar_style(avatar, size = RaftComponents::AVATAR_SMALL_SIZE)
      "--avatar-url: url(%s); --avatar-size: %spx" % [avatar_url(avatar, size), size]
    end

    def initials_url(name:, hue: nil)
      "/initials/#{ERB::Util.url_encode(name)}"
    end

    #
    # generate a dicebar avatar url, using either a name (for initial avatars)
    # or a seed (for icon avatars).
    #
    def dicebear_url(name: nil, seed: nil, radius: nil, hair_color: nil, skin_color: nil, bg_color: nil, hue: nil, mouth: nil)
      if seed.nil?
        # no seed, so use the name for the initials.
        # the color is more saturated and less bright than when used with
        # picture avatars.
        if hue
          bg_color = hue_to_hex(hue, 60, 60)
        end
        type = "initials"
        seed = name
      else
        if hue
          bg_color = hue_to_hex(hue, 60, 70)
        end
        type = "avataaars"
      end
      radius  = radius&.to_i || 10

      params = {
        "seed" => seed,
        "hairColor" => hair_color,
        "skinColor" => skin_color,
        "backgroundColor" => bg_color,
        "mouth" => mouth,
        "radius" => radius
      }
      params.select! {|k,v| v.present? }
      # to_query escapes each array entry before joining, i don't understand
      # why they choose to not mark it as html_safe by default.
      safe_join([Conf.dicebear_public_url,  "/9.x/#{type}/svg?",  params.to_query.html_safe])
    end

    private

    def helper_context
      defined?(helpers) ? helpers : self
    end
  end
end
