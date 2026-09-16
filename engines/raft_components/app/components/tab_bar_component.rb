#
# There are two different behaviors for tabs: with javascript and without.
#
# JAVASCRIPT
#
# For the javascript variant, all the tab contents are rendered,
# and changing the tab just shows and hides the different content areas.
#
# = v.tab_bar(js: true) do |tabs|
#   - tabs.with_tab(label: "Info", active: true) do
#      = render 'info'
#   - tabs.with_tab(label: "Edit") do
#      = render 'edit'
#
# NON-JAVASCRIPT
#
# For the non-javascript variant, only the content area that is associated with the
# active tab gets rendered. Also, `url` is required
#
# = v.tab_bar do |tabs|
#   - tabs.with_tab(label: "Info", url: "...", active: true) do
#      = render 'info'
#   - tabs.with_tab(label: "Edit", url: "...") do
#      = render 'edit'
#      - raise Exception, "this is not called because the tab is not active"
#

class TabBarComponent < ApplicationComponent
  attr_accessor :javascript, :tab_bar_id

  renders_many :tabs, TabComponent
  renders_one :endmatter

  haml_template <<~HAML
    - if @javascript
      .nav.nav-tabs
        - tabs.each do |tab|
          = tab
      .tab-content.mt-3
        - tabs.each do |tab|
          .tab-pane{id: tab.tab_id, class: tab.pane_class}
            = tab.content
    - else
      %ul.nav.nav-tabs
        - tabs.each do |tab|
          = tab
        - if endmatter?
          %li.nav-item.d-flex.align-items-center(style='margin-left: auto')
            = endmatter
      .tab-content.mt-3
        - tabs.each do |tab|
          = tab.content if tab.active?
  HAML

  def initialize(**kwargs)
    super(**kwargs)
    @javascript = kwargs.delete(:js)
    if @javascript
      @tab_bar_id = "tabs_#{rand(1_000_000_000)}"
    end
  end
end
