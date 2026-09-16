#
# creates a row of links with icons. these are aligned so the icon appears in the vertical center and
# is compatible with an avatar link
#
# = v.icon_row do |row|
#   - row.with_avatar(...)
#   - row.with_link('stop-sign', link_to("No!", ...))
#   - row.with_link('go-sign', link_to("Yes!", ...))
#

class IconRowComponent < ApplicationComponent
  haml_template <<~HAML
    .d-flex.align-items-center.xxx
      - avatars.each do |avatar|
        .me-3= avatar
      - links.each do |link|
        .me-3
          %span.avatar.flex= link
  HAML

  def initialize
  end

  renders_many :avatars, ->(avatar) do
    avatar
  end

  renders_many :links, ->(*args, &block) do
    if args.count == 1
      icon = nil
      link = args.first
    else
      icon, link = args
    end
    if icon
      icon(icon: icon) + '&nbsp;'.html_safe + link
    else
      link
    end
  end
end
