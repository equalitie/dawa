require "test_helper"

#
# Tests for the shared VegaChartHelper builders. These are the primitives that
# both container graphs and the future VictoriaMetrics host graphs are built
# from; keeping them pinned here protects the reuse contract.
#
class VegaChartHelperTest < ActiveSupport::TestCase
  include VegaChartHelper

  setup do
    @points = [ { time: 1_730_000_000_123, usage_mb: 12.5, up: 90.0, down: 10.0 } ]
  end

  test "vega_area_spec builds a single-series area spec" do
    spec = vega_area_spec(
      @points,
      title: "Usage",
      y_field: "usage_mb",
      y_title: "MB",
      color: "#123456",
      tooltip: [ { field: "usage_mb", type: "quantitative", title: "MB", format: ".1f" } ]
    )

    assert_equal "chartdata", spec.dig(:data, :name)
    assert_equal "Usage", spec[:title]
    assert_equal "usage_mb", spec.dig(:encoding, :y, :field)
  end

  test "vega_area_spec applies an optional transform to derive the y field" do
    spec = vega_area_spec(
      @points,
      title: "Memory",
      y_field: "mem_mb",
      y_title: "MB",
      color: "#198754",
      transform: { calculate: "datum.mem_used / 1048576", as: "mem_mb" },
      tooltip: true
    )

    calc = spec[:transform].find { |t| t[:as] == "mem_mb" }
    refute_nil calc
    assert_equal "datum.mem_used / 1048576", calc[:calculate]
  end

  test "vega_folded_area_spec folds two fields and derives mbps + label" do
    spec = vega_folded_area_spec(
      @points,
      title: "Network",
      fold: [ "up", "down" ],
      label_calc: "datum.direction == 'up' ? 'Up' : 'Down'",
      y_title: "MB/s",
      domain: [ "up", "down" ],
      range: [ "#111111", "#222222" ],
      tooltip: true
    )

    fold = spec[:transform].find { |t| t[:fold] }
    assert_equal [ "up", "down" ], fold[:fold]

    mbps = spec[:transform].find { |t| t[:as] == "mbps" }
    assert_equal "datum.bytes / 1048576", mbps[:calculate]

    label = spec[:transform].find { |t| t[:as] == "direction_label" }
    assert_equal "datum.direction == 'up' ? 'Up' : 'Down'", label[:calculate]

    assert_equal "mbps", spec.dig(:encoding, :y, :field)
    assert_equal [ "#111111", "#222222" ], spec.dig(:encoding, :color, :scale, :range)
  end

  test "stacked series hover circle rides the stacked y position" do
    spec = vega_series_area_spec(
      @points,
      title: "Network",
      y_field: "usage_mb",
      y_title: "Mbit/s",
      color_field: "series",
      domain: [ "ingress", "egress" ],
      range: [ "#0d6efd", "#198754" ],
      tooltip: [ { field: "value", type: "quantitative" } ],
      stack: true
    )

    hover = spec[:layer].find { |l| l[:mark][:type] == "circle" }
    refute_nil hover, "expected a hover tooltip layer"
    assert_equal "usage_mb", hover.dig(:encoding, :y, :field)
    # Explicitly stacked so the hover circle sits on the stacked series.
    assert_equal "zero", hover.dig(:encoding, :y, :stack)
    refute_nil hover.dig(:encoding, :tooltip), "expected the tooltip on the hover circle"
  end

  test "unstacked series hover circle stays unstacked" do
    spec = vega_series_area_spec(
      @points,
      title: "Disk",
      y_field: "usage_mb",
      y_title: "GB",
      color_field: "series",
      domain: [ "free", "used" ],
      range: [ "#198754", "#fd7e14" ],
      tooltip: [ { field: "value", type: "quantitative" } ],
      stack: false
    )

    hover = spec[:layer].find { |l| l[:mark][:type] == "circle" }
    refute_nil hover, "expected a hover tooltip layer"
    assert_equal false, hover.dig(:encoding, :y, :stack)
  end
end
