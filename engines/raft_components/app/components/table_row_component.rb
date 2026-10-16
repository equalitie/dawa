class TableRowComponent < TableBaseComponent
  renders_many :cells, "TableCellComponent"
  eager_slot :cells

  attr_accessor :parent

  haml_template <<~HAML
    %tr{**@html, data: @data}
      - cells.each_with_index do |cell, index|
        - cell_classes(cell, index)
        = cell
  HAML

  def initialize(hover: true, **kwargs)
    @hover = hover
    super
  end

  def hover
    parent&.hover&.presence || @hover
  end

  def cell_classes(cell, index)
    cell.options[:class] = cell_class_list(cell, index).join(" ")
  end

  def cell_class_list(cell, index, hover: self.hover)
    given = cell.options[:class].to_s.sub(/\s*position-relative\b/, "")
    [
      columns_definition&.[](index)&.fetch(:class),
      given,
      (hover ? "position-relative" : nil)
    ].compact.reject(&:empty?)
  end
end
