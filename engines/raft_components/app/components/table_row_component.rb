class TableRowComponent < TableBaseComponent
  renders_many :cells, "TableCellComponent"
  eager_slot :cells

  attr_accessor :parent

  haml_template <<~HAML
    %tr{**@html}
      - cells.each_with_index do |cell, index|
        - cell_classes(cell, index)
        = cell
  HAML

  def initialize(hover: true, **kwargs)
    @hover = hover
    super
  end

  def columns_definition
    parent&.columns_definition&.presence || @columns_definition
  end

  def hover
    parent&.hover&.presence || @hover
  end

  def cell_classes(cell, index)
    cell.options[:class] = [
      columns_definition&.[](index)&.fetch(:class),
      cell.options[:class],
      (hover ? "position-relative" : nil)
    ].compact
  end
end
