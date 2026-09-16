
class GetButtonComponent < ButtonComponent
  self.button_type  = "submit"
  self.default_method = "get"
  self.hidden_form  = true

  def initialize(**kwargs)
    if kwargs[:url]
      kwargs[:params] ||= extract_params(kwargs[:url])
      kwargs[:url] = remove_params(kwargs[:url])
    end
    super
  end

end
