#
# TABLE
#
# What? Tables are simple, they don't need their own component!
#
# Well, yes and no. We use a very particular kind of table
# quiet a lot, and it needs particular markup that is not so simple.
#
# This component defaults to a table with hover rows, stretched links
# and auto truncating & hiding columns.
#
# = v.table do |t|
#   - t.column(size: :shrink, label: "Quote")
#   - t.with_row do |r|
#     - r.with_cell do
#       Since it seems that any heart which beats for freedom has
#       the right only to a lump of lead, I too claim my share
#
class TableComponent < TableBaseComponent
  renders_many :rows, "TableRowComponent"
  eager_content

  haml_template <<~HAML
    %table{class: table_classes}
      - if column_labels?
        %tr
          - columns_definition.each do |column|
            %th{class: column[:class]}
              = column[:label]
      - if rows?
        - rows.each do |row|
          = row
      - elsif content.present?
        = content
      - else
        %tr#empty-row
          %td{colspan: columns_definition.count}
            - if @label
              = t("components.no_thing", thing: @label.pluralize)
            - else
              = t("components.none")
  HAML

  def initialize(label = nil, hover: true, centered: true, **kwargs)
    @hover = hover
    @label = label
    @centered = centered
    super(**kwargs)
  end

  def table_classes
    "table table-headerless table-shrink table-hover align-middle #{@html[:class]}"
  end

  def column_labels?
    columns_definition.each do |col|
      return true if col[:label].present?
    end
    false
  end
end
