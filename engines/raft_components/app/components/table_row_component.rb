class TableRowComponent < TableBaseComponent
  renders_many :cells, "TableCellComponent"
  eager_slot :cells

  attr_accessor :parent

  haml_template <<~HAML
    -#
      @html gives raw attributes; @data renders `data:` as data-* attributes (Stimulus
      targets/actions, and the log explorer's row dedupe key).
    %tr{**@html, data: @data}
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
    cell.options[:class] = cell_class_list(cell, index).join(" ")
  end

  #
  # The full class list for one cell: the column's classes, then any classes the cell was
  # given directly, then the hover marker.
  #
  # Exposed (not just assigned) because the row template puts the result on the <td>, but a
  # client that rebuilds a row outside the template -- the log explorer's JSON refresh -- has
  # to reproduce it exactly. Publishing the same computation keeps the two halves of
  # "a live row looks like a loaded row" from drifting apart, which is how the log table's
  # severity stripe ended up looking different on appended rows.
  #
  # Idempotent: the class this method writes is one of the inputs it reads, so it strips any
  # hover marker it previously appended. Without that, rendering a row twice (ViewComponent
  # evaluates eager content and then renders) would double the class.
  #
  def cell_class_list(cell, index, hover: self.hover)
    given = cell.options[:class].to_s.sub(/\s*position-relative\b/, "")
    [
      columns_definition&.[](index)&.fetch(:class),
      given,
      (hover ? "position-relative" : nil)
    ].compact.reject(&:empty?)
  end
end
