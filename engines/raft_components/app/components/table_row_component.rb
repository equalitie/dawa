class TableRowComponent < ApplicationComponent
  renders_many :cells, "TableCellComponent"
  eager_slot :cells

  attr_accessor :parent

  haml_template <<~HAML
    %tr
      - cells.each_with_index do |cell, index|
        - cell_classes(cell, index)
        = cell
  HAML

  def initialize(**kwargs)
    super
  end

  def cell_classes(cell, index)
    cell.options[:class] = [
      parent.columns[index]&.fetch(:class),
      cell.options[:class],
      (parent.hover ? "position-relative" : nil)
    ].compact
  end
end
