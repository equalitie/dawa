class TimelineComponent < ApplicationComponent
  renders_many :items, ->(options = {}, &block) do
    content_tag(:li, class: "timeline-item ps-3 pb-3 #{options[:class]}") do
      content_tag(:div, class: "timeline-body flex-fill", &block)
    end
  end

  haml_template <<~HAML
    %ul.timeline{class: @html[:class]}
      - items.each do |item|
        = item
  HAML

  def initialize(**kwargs)
    super
  end
end
