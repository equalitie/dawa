#
# renders a button. if you click the button, the list_url
# html is loaded into an autocomplete list. when an item is selected
# the closest form is submitted with an added hidden element
# to encode the selected value as a parameter with name
# specified by `name` argument.
#
# alternately, if submit = false, then the autocomplete
# will append the selected element & hidden field above the button,
# assuming the button is inside a form that will be submitted
# elsewhere.
#
class AutocompleteButtonComponent < ButtonComponent
  self.hidden_form = false

  haml_template <<~HAML
    %div{
      "data-controller" => "autocomplete",
      "data-autocomplete-url-value" => @url,
      "data-autocomplete-submit-name-value" => @submit_name,
      "data-autocomplete-submit-on-select-value" => @submit.inspect,
      "data-autocomplete-choice-attribute-value" => "data-value",
    }
      - if !@submit
        .mb-2{"data-autocomplete-target" => "append"}
      = button_tag
      - if content?
        %div.d-none{"data-autocomplete-target" => "template"}
          = content
  HAML

  def initialize(name, url:, submit: true, **kwargs)
    super(**kwargs)
    @submit_name = name
    @url = url
    @submit = submit
    @data["action"] = "click->autocomplete#open"
  end

end
