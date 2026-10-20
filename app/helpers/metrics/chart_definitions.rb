#
# Chart Definitions
#
# Each chart definition is a Hash keyed by chart id:
#
#   id =>
#     title          display title
#     kind           :single       -- one query, rendered as a single area
#                    :series       -- one query per [:series] entry, each tagged and layered
#     y_title        y-axis label
#     series         (kind :series) [[label, color], ...], order = stack/render order
#     stack          whether series layer (stack) on top of one another (default true)
#     y_axis_format  optional, e.g. "%" appended to values
#     queries        (kind :series) one PromQL string per [:series] entry
#     query          (kind :single) the single PromQL string
#
#   Queries may interpolate %{range}, the per-window time-window over which each data
#   point is aggregated (supplied from the WINDOW_RANGES mapping).
#
module Metrics::ChartDefinitions
  def chart_definition(name)
    CHARTS[name.to_s]
  end

  CHARTS = {
    # CPU busied per mode, stacked; every core's modes together add to ~100%. Each mode is its
    # own query, expressed as a share of total CPU time so the stack sums to ~100%. `range` is
    # applied inside each `rate(...)`.
    "host_cpu" => {
      title: "charts.cpu",
      kind: :series,
      color_field: "series",
      y_title: "%",
      stack: true,
      series: [
        # idle is drawn first (top of the stack in this layer order); light grey so it recedes,
        # with the busy modes visualised beneath toward the bottom.
        [ "idle",    "#cfd4da" ],
        [ "user",    "#0d6efd" ],
        [ "system",  "#198754" ],
        [ "nice",    "#fd7e14" ],
        [ "io_wait", "#dc3545" ]
      ],
      y_axis_format: "d",
      # Each mode = its share of total CPU seconds across all cores (order matches [:series]).
      queries: %w[idle user system nice io_wait].map do |mode|
        <<~PROM
          100 * sum(rate(host_cpu_seconds_total{mode="#{mode}"}[%{range}])) / sum(rate(host_cpu_seconds_total[%{range}]))
        PROM
      end
    },

    # Memory available + used, in GB. Stacked together they show the volume picture of
    # the machine's memory (available is roughly total minus used/caches at a given
    # instant, so the two don't sum exactly to installed RAM).
    "host_memory" => {
      title: "charts.memory",
      kind: :series,
      color_field: "series",
      y_title: "GB",
      stack: true,
      series: [
        [ "available", "#198754" ],
        [ "used",      "#0d6efd" ]
      ],
      queries: [
        <<~PROM,
          avg_over_time(host_memory_available_bytes[%{range}]) / 1024 / 1024 / 1024
        PROM
        <<~PROM
          avg_over_time(host_memory_used_bytes[%{range}]) / 1024 / 1024 / 1024
        PROM
      ]
    },

    # Root filesystem: free + used, in GB. Stacked.
    "host_disk" => {
      title: "charts.disk",
      kind: :series,
      color_field: "series",
      y_title: "GB",
      stack: true,
      series: [
        [ "free", "#198754" ],
        [ "used", "#fd7e14" ]
      ],
      queries: [
        <<~PROM,
          avg_over_time(host_filesystem_free_bytes{mountpoint="/"}[%{range}]) / 1024 / 1024 / 1024
        PROM
        <<~PROM
          avg_over_time(host_filesystem_used_bytes{mountpoint="/"}[%{range}]) / 1024 / 1024 / 1024
        PROM
      ]
    },

    # Network throughput: ingress + egress stacked, in Mbit/s, skipping loopback/virtual.
    "host_network" => {
      title: "charts.network",
      kind: :series,
      color_field: "series",
      y_title: "Mbit/s",
      stack: true,
      series: [
        [ "ingress", "#0d6efd" ],
        [ "egress",  "#198754" ]
      ],
      queries: [
        <<~PROM,
          sum(rate(host_network_receive_bytes_total{device!~"lo|docker.*|veth.*|br-.*|tailscale.*|virbr.*", device!=""}[%{range}])) * 8 / 1000000
        PROM
        <<~PROM
          sum(rate(host_network_transmit_bytes_total{device!~"lo|docker.*|veth.*|br-.*|tailscale.*|virbr.*", device!=""}[%{range}])) * 8 / 1000000
        PROM
      ]
    }
  }.freeze
end
