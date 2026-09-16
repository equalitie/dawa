#
# abstract superclass of table components
#
class TableBaseComponent < ApplicationComponent
  attr_accessor :columns_definition, :hover

  def columns(array)
    array.each do |col|
      column(*col)
    end
  end

  def column(*args)
    @columns_definition ||= []
    classes = []
    label = nil
    args.each do |arg|
      if arg.is_a? Symbol
        classes << "fit" if arg == :shrink
        classes << "truncate-auto" if arg == :grow
        classes << "text-end" if arg == :end
        classes << "text-nowrap" if arg == :nowrap
        classes << "d-none d-md-table-cell" if arg == :hide_sm
        classes << "d-none d-lg-table-cell" if arg == :hide_md
      elsif arg.is_a? String
        label = arg
      end
    end
    @columns_definition << { class: classes.join(" "), label: label }
  end

  #
  # a useful link_to just for tables.
  #
  def link_to(*args, **kwargs)
    if args[0] && args[1].nil?
      return args[0]
    end
    if hover
      kwargs[:class] = [ "stretched-link hover-link", kwargs[:class] ].join(" ")
    end
    helpers.link_to(*args, **kwargs)
  end
end
