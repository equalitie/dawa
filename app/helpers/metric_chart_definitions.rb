#
# Graph Definitions
#
#   * HOST_CHARTS      -- metrics about the hypervisor host itself, exported by Vector's
#                         host_metrics source. These are all tagged with the same single
#                         host, so the PromQL no longer filters on an `instance` label.
#
#   * CONTAINER_CHARTS -- metrics about individual containers/services (from logporter /
#                         docker metrics).
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
module MetricChartDefinitions
  # window token (matches the UI tab and the controller param) => the duration over which
  # a single graph point is averaged. Choosing the range equal to one sample-advance means
  # consecutive points tile the window with no gaps, and roughly:
  #
  #   day(24h)/5m  = 288 pts
  #   week(7d)/30m = 336 pts
  #   month(30d)/2h = 360 pts
  #   quarter(90d)/6h = 360 pts
  #
  WINDOW_RANGES = {
    "day"     => "5m",
    "week"    => "30m",
    "month"   => "2h",
    "quarter" => "6h"
  }.freeze

  HOST_CHARTS = {
    # CPU busied per mode, stacked; every core's modes together add to ~100%. Each mode is its
    # own query, expressed as a share of total CPU time so the stack sums to ~100%. `range` is
    # applied inside each `rate(...)`.
    "cpu" => {
      title: "CPU",
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
    "memory" => {
      title: "Memory",
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
    "disk" => {
      title: "Disk",
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
    "network" => {
      title: "Network",
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

  CONTAINER_CHARTS = {}.freeze
end
