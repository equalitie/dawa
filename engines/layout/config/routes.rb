Rails.application.routes.draw do
  if Rails.env.development?
    # galleries
    get "/dev" => "dev#index"
    get "/dev/components" => "dev#components"
    get "/dev/layout" => "dev#layout"
    get "/dev/columns" => "dev#columns"
    get "/dev/images" => "dev#images"
    get "/dev/widgets" => "dev#widgets"

    # testing actions
    post "/dev/button_action" => "dev#button_action"
    get "/dev/autocomplete_list" => "dev#autocomplete_list"
    put "/dev/submit_form" => "dev#submit_form"
    post "/dev/submit_form" => "dev#submit_form"
  end
end
