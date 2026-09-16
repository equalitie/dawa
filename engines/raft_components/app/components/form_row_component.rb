class FormRowComponent < ApplicationComponent

#haml_template <<-HAML
#%div.mb-3
#  xxx
#HAML

#%label(for="xxx" class="form-label")= content

    renders_one :label, ->(for: "") do
      content_tag(:label, for: "", class: "form-label") { content }
    end

    #renders_one :label, FormLabelComponent

    def initialize
    end

    def call
      content_tag(:div, class: "mb-3") {
        label }
    end

  end
