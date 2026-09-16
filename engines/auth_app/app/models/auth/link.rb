#
# Sharable capabilities link
#

module Auth
  class Link < ApplicationRecord
    #belongs_to :workspace
    belongs_to :linkable, polymorphic: true, optional: true

    attribute :max_uses, default: 10
    attribute :used_count, default: 0
    enum :role, [ :none, :view, :comment, :edit, :admin ], prefix: true, default: :none

    validates :expires_at, presence: true
    validates :expires_at, comparison: { less_than: -> { 8.weeks.from_now } }, on: :create
    validates :max_uses, comparison: { greater_than: 0, less_than: 1000 }

    scope :pending, -> { where("used_count < max_uses AND expires_at > ?", Time.now) }
    scope :used, -> { where("used_count >= max_uses") }
    scope :expired, -> { where("expires_at < ?", Time.now) }
    scope :updated_at, -> { order(updated_at: :desc) }

    # these are set in memory after a secret is loaded
    # from an encrypted url.
    attr_accessor :secret

    #
    # FINDING
    #

    def to_code(current_vault)
      if !expired? && link_key
        secret = current_vault.get(self.workspace)
        Secrets::EncryptedUrl.encrypt_with_key(
          Secrets::IntegerEncoder.encode(self.id, secret),
          id: link_key.id, key: link_key.key
        )
      end
    end

    def self.find_by_code(str)
      decrypted = Secrets::EncryptedUrl.decrypt_with_key(str) { |key_id|
        LinkKey.find_by_id(key_id)&.key
      }
      if decrypted
        link_id, secret = Secrets::IntegerEncoder.decode(decrypted)
        link = Link.find_by_id(link_id)
        if link
          link.secret = secret.unpack("H*").first # binary to hex
          link
        end
      end
    end

    #
    # ACCESSORS
    #

    def used?
      used_count >= max_uses
    end

    def expired?
      expires_at < Time.now
    end

    def disabled?
      used? || expired?
    end

    def disabled_reason
      if used?
        "used"
      elsif expired?
        "expired"
      end
    end

    def state
      if used?
        "used"
      elsif expired?
        "expired"
      else
        "pending"
      end
    end

    def link_key
      @link_key ||= LinkKey.find_or_create_by!(expires_on: self.expires_at.advance(days: 1).utc.to_date)
    end

    #
    # METHODS
    #
    def link_for?(linkable)
      #self.workspace_id == linkable.workspace_id &&
        self.linkable == linkable
    end

    def grants_access_to?(linkable)
      #self.workspace_id == linkable.workspace_id &&
        self.linkable.grants_access_to?(linkable)
    end

    # should this link open directly into an editor for viewing or editing?
    def editable?
      (linkable.respond_to?(:editable?) && linkable.editable?) ||
      (linkable.respond_to?(:viewable?) && linkable.viewable?)
    end
  end
end
