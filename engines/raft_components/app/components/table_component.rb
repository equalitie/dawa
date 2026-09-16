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
class TableComponent < ApplicationComponent
  renders_many :rows, "TableRowComponent"
  eager_content

  attr_accessor :columns, :hover

  haml_template <<~HAML
    %table{class: table_classes}
      - if column_labels?
        %tr
          - @columns.each do |column|
            %th{class: column[:class]}
              = column[:label]
      - if rows?
        - rows.each do |row|
          = row
      - else
        %tr#empty-row
          %td{colspan: @columns.count}
            - if @label
              = t("components.no_thing", thing: @label.pluralize)
            - else
              = t("components.none")
  HAML

  def initialize(label = nil, hover: true, centered: true, **kwargs)
    @columns = []
    @hover = hover
    @label = label
    @centered = centered
    super(**kwargs)
  end

  def table_classes
    "table table-headerless table-shrink table-hover align-middle #{@html[:class]}"
  end

  def column_labels?
    @columns.each do |col|
      return true if col[:label].present?
    end
    false
  end

  def column(*args, label: nil)
    classes = []
    args.each do |arg|
      classes << "fit" if arg == :shrink
      classes << "truncate-auto" if arg == :grow
      classes << "text-end" if arg == :end
      classes << "text-nowrap" if arg == :nowrap
      classes << "d-none d-md-table-cell" if arg == :hide_sm
      classes << "d-none d-lg-table-cell" if arg == :hide_md
    end
    @columns << { class: classes.join(" "), label: label }
  end

  #
  # a useful link_to just for tables.
  #
  def link_to(*args, **kwargs)
    if args[0] && args[1].nil?
      return args[0]
    end
    if @hover
      kwargs[:class] = [ "stretched-link hover-link", kwargs[:class] ].join(" ")
    end
    helpers.link_to(*args, **kwargs)
  end
end
