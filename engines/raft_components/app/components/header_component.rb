#
# displays an attractive header area for a 'show' or 'edit' view of a record.
#

class HeaderComponent < ApplicationComponent
  haml_template <<~HAML
    .d-flex.align-items-center.justify-content-between{class: @css_class}
      %h2.m-0
        = @title1
        = @title2
        - if @secondary_text
          %span.text-secondary{style: "font-weight: normal"}
            = @secondary_text
      - if @right_text
        .text-right
          = @right_text
  HAML

  def initialize(object = nil, title: nil, gray: nil, grey: nil, right: nil, css_class: nil)
    if object
      @title1 = object.class.name.demodulize.titleize
      @title2 = object.to_param
      @secondary_text = object.created_at.to_date
    else
      if title.is_a?(Array)
        @title1, @title2 = title
      else
        @title1 = title
      end
      @secondary_text = gray || grey
    end
    @right_text = right
    if @right_text.is_a?(Array)
      @right_text = content_tag(:span, class: 'd-flex gap-1') {
        safe_join(
          @right_text.map { |item|
            content_tag(:span) { item }
          }
        )
      }
    end
    @css_class = css_class
  end
end
