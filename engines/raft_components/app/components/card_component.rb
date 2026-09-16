#
# Renders bootstrap 5 card component
#
class CardComponent < ApplicationComponent
  renders_one :header
  renders_one :header_end
  renders_one :image
  renders_one :table
  renders_one :list, "ListComponent"
  renders_one :footer

  haml_template <<~HAML
    .card
      - if header? || @header || header_end? || @header_end
        .card-header.d-flex
          .flex-grow-1= @header || header
          .flex-shrink-1= @header_end || header_end
      - if image?
        = image
      - if table?
        = table
      - if list?
        = list
      - if content.present? || @title
        .card-body
          - if @title
            .card-title= @title
          .card-text
            = content
      - if footer?
        .card-footer
          = footer
  HAML

  def initialize(title: nil, header: nil, header_end: nil, **kwargs)
    super
    @title = title
    @header = header
    @header_end = header_end
  end

  class ListComponent < ApplicationComponent
    renders_many :items

    def call
      if items?
        content_tag(:ul, class: "list-group list-group-flush") {
          safe_join(items.map { |item|
            content_tag(:li, item, class: "list-group-item")
          })
        }
      end
    end
  end
end
