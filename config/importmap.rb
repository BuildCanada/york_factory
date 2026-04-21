pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "sortablejs", to: "https://ga.jspm.io/npm:sortablejs@1.15.6/modular/sortable.esm.js"

pin_all_from "app/javascript/controllers", under: "controllers"
pin "@rails/activestorage", to: "activestorage.esm.js"
pin "@avo-hq/marksmith", to: "https://ga.jspm.io/npm:@avo-hq/marksmith@0.4.8/dist/marksmith.esm.js"
