#
# Builds Vega-Lite area chart specifications for container resource usage.
#
# Each chart uses a named data source ("chartdata") so the client can stream
# new points into the live chart via view.change("chartdata", points).runAsync()
# without re-generating the spec on every poll.
#
# Charts are layered: an area mark for the trend, plus an invisible circle
# layer that shows a tooltip with the data point's details on hover.
#
module ContainerStatsHelper
  def container_stats_charts(points)
    {
      "cpu"  => cpu_area_spec(points),
      "memory" => memory_area_spec(points),
      "network" => network_area_spec(points),
      "block_io" => block_io_area_spec(points)
    }
  end

  def cpu_area_spec(points)
    Vega.lite
      .data(name: "chartdata", values: points)
      .width("container")
      .height(120)
      .autosize(streaming_autosize)
      .title("CPU")
      .encoding(
        x: { field: "time", type: "temporal", axis: { title: nil } },
        y: { field: "cpu_pct", type: "quantitative", title: "%", scale: { domain: [ 0, 100 ] } }
      )
      .layer(area_marks(interpolate: "monotone", color: "#0d6efd", opacity: 0.6).push(
        hover_tooltip_layer([
          { field: "time", type: "temporal", title: "Time", format: "%H:%M:%S" },
          { field: "cpu_pct", type: "quantitative", title: "CPU", format: ".1f" }
        ])
      ))
      .spec
  end

  def memory_area_spec(points)
    Vega.lite
      .data(name: "chartdata", values: points)
      .width("container")
      .height(120)
      .autosize(streaming_autosize)
      .title("Memory")
      .transform(calculate: "datum.mem_used / 1048576", as: "mem_mb")
      .encoding(
        x: { field: "time", type: "temporal", axis: { title: nil } },
        y: { field: "mem_mb", type: "quantitative", title: "MB" }
      )
      .layer(area_marks(interpolate: "monotone", color: "#198754", opacity: 0.6).push(
        hover_tooltip_layer([
          { field: "time", type: "temporal", title: "Time", format: "%H:%M:%S" },
          { field: "mem_mb", type: "quantitative", title: "Memory", format: ".1f" }
        ])
      ))
      .spec
  end

  #
  # Network RX/TX in MB/s, color-coded by direction.
  #
  def network_area_spec(points)
    Vega.lite
      .data(name: "chartdata", values: points)
      .width("container")
      .height(120)
      .autosize(streaming_autosize)
      .title("Network")
      .transform([
        { fold: [ "net_rx", "net_tx" ], as: [ "direction", "bytes" ] },
        { calculate: "datum.bytes / 1048576", as: "mbps" },
        { calculate: "datum.direction == 'net_rx' ? 'RX' : 'TX'", as: "direction_label" }
      ])
      .encoding(
        x: { field: "time", type: "temporal", axis: { title: nil } },
        y: { field: "mbps", type: "quantitative", title: "MB/s" },
        color: { field: "direction", type: "nominal", title: nil,
                 scale: { domain: [ "net_rx", "net_tx" ],
                          range: [ "#198754", "#0d6efd" ] },
                 legend: { orient: "top" } }
      )
      .layer([
        { mark: { type: "area", interpolate: "monotone", opacity: 0.5 } },
        hover_tooltip_layer([
          { field: "time", type: "temporal", title: "Time", format: "%H:%M:%S" },
          { field: "direction_label", type: "nominal", title: "Direction" },
          { field: "mbps", type: "quantitative", title: "MB/s", format: ".2f" }
        ])
      ])
      .spec
  end

  #
  # Block I/O read/write in MB/s, color-coded by direction.
  #
  def block_io_area_spec(points)
    Vega.lite
      .data(name: "chartdata", values: points)
      .width("container")
      .height(120)
      .autosize(streaming_autosize)
      .title("Block I/O")
      .transform([
        { fold: [ "blk_read", "blk_write" ], as: [ "direction", "bytes" ] },
        { calculate: "datum.bytes / 1048576", as: "mbps" },
        { calculate: "datum.direction == 'blk_read' ? 'Read' : 'Write'", as: "direction_label" }
      ])
      .encoding(
        x: { field: "time", type: "temporal", axis: { title: nil } },
        y: { field: "mbps", type: "quantitative", title: "MB/s" },
        color: { field: "direction", type: "nominal", title: nil,
                 scale: { domain: [ "blk_read", "blk_write" ],
                          range: [ "#dc3545", "#ffc107" ] },
                 legend: { orient: "top" } }
      )
      .layer([
        { mark: { type: "area", interpolate: "monotone", opacity: 0.5 } },
        hover_tooltip_layer([
          { field: "time", type: "temporal", title: "Time", format: "%H:%M:%S" },
          { field: "direction_label", type: "nominal", title: "Direction" },
          { field: "mbps", type: "quantitative", title: "MB/s", format: ".2f" }
        ])
      ])
      .spec
  end

  private

  #
  # With width: "container", Vega-Lite doesn't re-measure layout on every data
  # update by default, so a grown y-axis label can get clipped after streaming.
  # Setting autosize.resize true recomputes the layout on each view update.
  # See: https://vega.github.io/vega-lite/docs/size.html#autosize
  #
  def streaming_autosize
    { resize: true }
  end

  #
  # The base area mark layer (used where encoding is shared across layers).
  #
  def area_marks(interpolate:, color:, opacity:)
    [
      { mark: { type: "area", interpolate: interpolate, color: color, opacity: opacity } }
    ]
  end

  #
  # An invisible circle layer that reveals a tooltip on hover.
  # Hidden markers are intentionally larger (size 80) to make hovering easier,
  # and their opacity goes to 0 when not hovered.
  #
  # Pass an explicit tooltip encoding array (list of { field:, type:, title: })
  # to whitelist which fields show in the tooltip, hiding derived fields like
  # the fold's direction/index and intermediate values.
  #
  def hover_tooltip_layer(tooltip = true)
    layer = {
      params: [
        {
          name: "hover",
          select: {
            type: "point",
            on: "pointerover",
            clear: "pointerout",
            # snap to the nearest data value to track the cursor over a moving chart
            nearest: true
          }
        }
      ],
      mark: { type: "circle", size: 80 },
      encoding: {
        opacity: {
          condition: { test: { param: "hover", empty: false }, value: 1 },
          value: 0
        }
      }
    }
    layer[:encoding][:tooltip] = tooltip if tooltip.is_a?(Array)
    layer
  end
end
