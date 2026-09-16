// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails";
import "controllers";

// vega charts
import "vega";
import "vega-lite";
import "vega-embed";

// Non-blocking: let the UMD globals (window.vega, window.vegaLite,
// window.vegaEmbed) be assigned after the importmap modules execute, then
// notify the vega.rb inline embed scripts (which register a listener for
// this event as a fallback when window.vegaEmbed isn't ready yet).
window.dispatchEvent(new Event("vega:load"));
