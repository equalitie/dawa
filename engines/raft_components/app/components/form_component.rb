
class FormComponent < ApplicationComponent
  renders_many :rows, FormRowComponent

  haml_template <<~HAML
    = form_with(**@args) do |form|
      - rows.each do |row|
        = row
  HAML

  def initialize(**args)
    @args = args
  end
end
