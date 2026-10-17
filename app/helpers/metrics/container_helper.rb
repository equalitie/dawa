#
# Builds Vega-Lite area chart specifications for container resource usage.
#
# This uses direct from docker stats, not victoria metrics like other charts.
#
# Each chart uses a named data source ("chartdata") so the client can stream
# new points into the live chart via view.change("chartdata", points).runAsync()
# without re-generating the spec on every poll. Spec-building primitives are
# shared with the metrics graphs via VegaChartHelper.
#
module Metrics::ContainerHelper
  include Metrics::VegaHelper

  def container_stats_charts(points)
    {
      "cpu"  => cpu_area_spec(points),
      "memory" => memory_area_spec(points),
      "network" => network_area_spec(points),
      "block_io" => block_io_area_spec(points)
    }
  end

  def cpu_area_spec(points)
    vega_area_spec(points,
      title: "CPU",
      y_field: "cpu_pct",
      y_title: "%",
      color: "#0d6efd",
      tooltip: [
        { field: "time", type: "temporal", title: "Time", format: "%H:%M:%S" },
        { field: "cpu_pct", type: "quantitative", title: "CPU", format: ".1f" }
      ])
  end

  def memory_area_spec(points)
    vega_area_spec(points,
      title: "Memory",
      y_field: "mem_mb",
      y_title: "MB",
      color: "#198754",
      transform: { calculate: "datum.mem_used / 1048576", as: "mem_mb" },
      tooltip: [
        { field: "time", type: "temporal", title: "Time", format: "%H:%M:%S" },
        { field: "mem_mb", type: "quantitative", title: "Memory", format: ".1f" }
      ])
  end

  #
  # Network RX/TX in MB/s, color-coded by direction.
  #
  def network_area_spec(points)
    vega_folded_area_spec(points,
      title: "Network",
      fold: [ "net_rx", "net_tx" ],
      label_calc: "datum.direction == 'net_rx' ? 'RX' : 'TX'",
      y_title: "MB/s",
      domain: [ "net_rx", "net_tx" ],
      range: [ "#198754", "#0d6efd" ],
      tooltip: [
        { field: "time", type: "temporal", title: "Time", format: "%H:%M:%S" },
        { field: "direction_label", type: "nominal", title: "Direction" },
        { field: "mbps", type: "quantitative", title: "MB/s", format: ".2f" }
      ])
  end

  #
  # Block I/O read/write in MB/s, color-coded by direction.
  #
  def block_io_area_spec(points)
    vega_folded_area_spec(points,
      title: "Block I/O",
      fold: [ "blk_read", "blk_write" ],
      label_calc: "datum.direction == 'blk_read' ? 'Read' : 'Write'",
      y_title: "MB/s",
      domain: [ "blk_read", "blk_write" ],
      range: [ "#dc3545", "#ffc107" ],
      tooltip: [
        { field: "time", type: "temporal", title: "Time", format: "%H:%M:%S" },
        { field: "direction_label", type: "nominal", title: "Direction" },
        { field: "mbps", type: "quantitative", title: "MB/s", format: ".2f" }
      ])
  end
end
