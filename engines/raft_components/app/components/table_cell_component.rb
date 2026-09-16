class TableCellComponent < ApplicationComponent
  attr_reader :options

  haml_template <<~HAML
    %td{ class: options[:class] }= content
  HAML

  def initialize(**options)
    @options = options
    super
  end
end
