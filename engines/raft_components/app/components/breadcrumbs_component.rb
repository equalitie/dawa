class BreadcrumbsComponent < ApplicationComponent
  attr_accessor :labels

  renders_many :buttons

  renders_many :crumbs, ->(active: false, &block) do
    label = block.call
    @labels << sanitize(label, tags: [])
    content_tag(:li, class: "text-break breadcrumb-item #{active ? 'active' : ''}", 'aria-current': "page") do
      label
    end
  end

  renders_one :home, ->(url, html: {}) do
    content_tag(:li, class: "breadcrumb-item") do
      link_to(icon(icon: "house-door-fill"), url, **html)
    end
  end

  def initialize(prev_url: nil, next_url: nil, **kwargs)
    super(**kwargs)
    @prev_url = prev_url
    @next_url = next_url
    @labels = []
  end


  haml_template <<~HAML
    .breadcrumb-bar
      %nav(aria-label="breadcrumb")
        %ol.mb-0.breadcrumb.breadcrumb-chevron
          - if home?
            = home
          - crumbs.each do |crumb|
            = crumb
      - buttons.each do |button|
        = button
      - if @prev_url
        %a.d-none.d-sm-flex.hover-bg-highlight.nav-link(href=@prev_url)
          = helpers.icon("chevron-left-thick")
      - if @next_url
        %a.d-none.d-sm-flex.hover-bg-highlight.nav-link(href=@next_url)
          = helpers.icon("chevron-right-thick")
  HAML
end
