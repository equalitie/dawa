pin "application"
pin "util"

# core rails
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/actioncable", to: "actioncable.esm.js"

# stimulus controllers
pin_all_from "app/javascript/controllers", under: "controllers", preload: false

# bootstrap
pin "bootstrap", to: "bootstrap.min.js", preload: true # 60k
pin "@popperjs/core", to: "popper.js", preload: true # 20k
