require "test_helper"

#
# Regression tests for the container resource-usage Vega chart specs.
#
# These pin the exact structural contract the client relies on when streaming
# via view.change("chartdata", changeset): a named "chartdata" dataset, a
# temporal x on "time", a layered area + hover-tooltip, and per-chart y/color
# fields. Because the specs are built through the shared VegaChartHelper, this
# also guards that shared refactor against drifting from the original output.
#
class Metrics::ContainerHelperTest < ActiveSupport::TestCase
  include Metrics::ContainerHelper

  setup do
    @points = [
      { time: 1_730_000_000_123, cpu_pct: 12.3, mem_used: 2_097_152,
        net_rx: 1024, net_tx: 2048, blk_read: 8, blk_write: 16 }
    ]
  end

  test "provides all four chart keys" do
    assert_equal %w[cpu memory network block_io], container_stats_charts(@points).keys
  end

  # every spec shares the streaming contract the front-end depends on
  test "each spec declares a chartdata dataset and temporal time encoding" do
    container_stats_charts(@points).each_value do |spec|
      assert_equal "chartdata", spec.dig(:data, :name)
      assert_equal "container", spec[:width]
      assert_equal 120, spec[:height]
      assert_equal({ resize: true }, spec[:autosize])
      assert_equal "temporal", spec.dig(:encoding, :x, :type)
      assert_equal "time", spec.dig(:encoding, :x, :field)
    end
  end

  test "each spec layers an area mark and a hover tooltip layer" do
    container_stats_charts(@points).each_value do |spec|
      marks = spec[:layer].map { |l| l[:mark][:type] }
      assert_includes marks, "area"
      assert_includes marks, "circle"
      assert spec[:layer].any? { |l| l[:params]&.any? { |p| p[:name] == "hover" } },
             "expected a hover tooltip layer"
    end
  end

  test "cpu chart maps cpu_pct to the y axis" do
    spec = container_stats_charts(@points)["cpu"]
    assert_equal "cpu_pct", spec.dig(:encoding, :y, :field)
    assert_equal "%", spec.dig(:encoding, :y, :title)
  end

  test "memory chart derives mem_mb and folds no direction" do
    spec = container_stats_charts(@points)["memory"]
    assert_equal "mem_mb", spec.dig(:encoding, :y, :field)
    calc = spec[:transform].find { |t| t[:as] == "mem_mb" }
    assert_equal "datum.mem_used / 1048576", calc[:calculate]
  end

  test "network and block_io charts fold two fields into a colored direction" do
    %w[network block_io].each do |key|
      spec = container_stats_charts(@points)[key]
      assert_equal "mbps", spec.dig(:encoding, :y, :field)
      assert_equal "direction", spec.dig(:encoding, :color, :field)
      assert_equal "nominal", spec.dig(:encoding, :color, :type)

      fold = spec[:transform].find { |t| t[:fold] }
      assert_equal 2, fold[:fold].size
      assert_equal %w[direction bytes], fold[:as]
    end
  end

  test "network colors rx green and tx blue" do
    spec = container_stats_charts(@points)["network"]
    assert_equal [ "net_rx", "net_tx" ], spec.dig(:encoding, :color, :scale, :domain)
    assert_equal [ "#198754", "#0d6efd" ], spec.dig(:encoding, :color, :scale, :range)
  end

  test "block_io colors read red and write amber" do
    spec = container_stats_charts(@points)["block_io"]
    assert_equal [ "blk_read", "blk_write" ], spec.dig(:encoding, :color, :scale, :domain)
    assert_equal [ "#dc3545", "#ffc107" ], spec.dig(:encoding, :color, :scale, :range)
  end
end
