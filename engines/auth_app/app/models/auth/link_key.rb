#
# Encryption keys for links. All links for all workspaces
# that expire on the same day share the same LinkKey.
#
# * by destroying expired LinkKey records, we ensure that
#   the secrets in encrypted Links cannot be used any more.
#
# * given a link url, you cannot determine what workspace
#   it belongs to after the LinkKey is destroyed
#   (before it is destroyed it could be any workspace that
#   has a link with the same expiration date)
#
# * If we stored the key in the Link record, it would be
#   possible for a sysadmin to reveal which workspace
#   a link was for, even after the key in the link was
#   cleared.
#

module Auth
  class LinkKey < ApplicationRecord
    self.table_name = "link_keys"

    attribute :key, default: -> { SecureRandom.random_bytes(32) }
    validates :expires_on, presence: true
  end
end
