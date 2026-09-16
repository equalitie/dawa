#
# Sharable capabilities link
#

class Link < ApplicationRecord
  self.table_name = "links"

  has_code length: 12, type: "mixed"

  belongs_to :linkable, polymorphic: true, optional: true

  attribute :max_uses, default: 10
  attribute :used_count, default: 0
  enum :role, [ :none, :view, :comment, :edit, :user, :admin ], prefix: true, default: :none

  validates :expires_at, presence: true
  validates :expires_at, comparison: { less_than: -> { 8.weeks.from_now } }, on: :create
  validates :max_uses, comparison: { greater_than: 0, less_than: 1000 }

  scope :pending, -> { where("used_count < max_uses AND expires_at > ?", Time.now) }
  scope :used, -> { where("used_count >= max_uses") }
  scope :expired, -> { where("expires_at < ?", Time.now) }
  scope :updated_at, -> { order(updated_at: :desc) }

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

  def good?
    !used? && !expired?
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

end
