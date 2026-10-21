#
# Chart Definitions
#
# Each chart definition is a Hash keyed by chart id. Common keys:
#
#   context        a :host chart or an :app chart
#   title          display title
#   y_title        y-axis label
#   stack          whether series layer (stack) on top of one another (default true)
#   y_axis_format  optional, e.g. "%" appended to values
#
# By kind:
#
#   kind: :single    one query, rendered as a single area.
#                    query    the single PromQL string
#
#   kind: :series    one query per [:series] entry, each tagged and layered. The set of
#                    series is fixed here, so colours are fixed with it.
#                    series   [[label, color], ...], order = stack/render order
#                    queries  one PromQL string per [:series] entry
#
#   kind: :dynamic   one query whose result is split into series by a label, so the set of
#                    series is only known once data arrives (one container per series).
#                    query          the PromQL string; it must keep the split label
#                    color_field    the row field to stack/legend by. Rows carry the label
#                                   posted into "series" (below), so this is normally "series".
#                    series_label   the metric label whose value is posted into the row's
#                                   "series" field
#                    legend_title   the legend heading, which also names the tooltip column
#
#   Queries may interpolate:
#
#   * %{range}, the per-window time-window over which each data
#     point is aggregated (supplied from the WINDOW_RANGES mapping). e.g. "5m", "2h"
#   * %{filter}, a PromQL label selector supplied by the caller, e.g. {dc_app="metrics"}.
#     Empty when no filter is given, so a template that uses it still works unfiltered.
#
module Metrics::ChartDefinitions
  def chart_definition(name)
    CHARTS[name.to_s]
  end

  def chart_definition_names
    CHARTS.keys
  end

  def host_chart_names
    chart_names_for(:host)
  end

  def app_chart_names
    chart_names_for(:app)
  end

  def chart_names_for(context)
    CHARTS.select { |_key, defn| defn[:context] == context }.keys
  end

  CHARTS = {
    # CPU busied per mode, stacked; every core's modes together add to ~100%. Each mode is its
    # own query, expressed as a share of total CPU time so the stack sums to ~100%. `range` is
    # applied inside each `rate(...)`.
    "host_cpu" => {
      context: :host,
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
      context: :host,
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
      context: :host,
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
      context: :host,
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
    },

    # Memory per container of one app, in MB, one stacked band per container.
    "app_memory" => {
      context: :app,
      title: "charts.memory",
      kind: :dynamic,
      # Rows are tagged into "series" by series_label, so that is the field to color by.
      color_field: "series",
      series_label: "containerName",
      legend_title: "Container",
      y_title: "MB",
      stack: true,
      query: %( avg_over_time(docker_memory_usage%{filter}[%{range}]) / 1024 / 1024 )
    },

    # CPU per container of one app, in percent of a single core, one stacked band per container.
    #
    # docker_cpu_usage_total is a COUNTER of CPU nanoseconds, so it takes rate(...) and never
    # avg_over_time: averaging a counter gives a meaningless number. rate() over nanoseconds is
    # ns/s; dividing by 1e9 gives cores, and multiplying by 100 gives percent of one core.
    # A multi-threaded container can therefore exceed 100, which is why this axis is not capped.
    "app_cpu" => {
      context: :app,
      title: "charts.cpu",
      kind: :dynamic,
      color_field: "series",
      series_label: "containerName",
      legend_title: "Container",
      y_title: "%",
      y_axis_format: "d",
      stack: true,
      query: %( sum by (containerName) (rate(docker_cpu_usage_total%{filter}[%{range}])) / 10000000 )
    },

    # Network throughput per container of one app, in Mbit/s, one stacked band per container
    # and direction.
    #
    # Docker exposes received and transmitted as two separate counters, but a stacked chart
    # needs each as its own series. label_replace rewrites containerName to "<container> / RX"
    # and "<container> / TX", so `sum by (containerName)` then yields one series per container
    # and direction. Folding direction into the name keeps it usable: the row model carries a
    # single "series" label, so a separate direction label would be dropped and every band
    # would collapse into one.
    #
    # rate() of bytes/s * 8 / 1e6 is Mbit/s.
    #
    "app_network" => {
      context: :app,
      title: "charts.network",
      kind: :dynamic,
      color_field: "series",
      series_label: "containerName",
      legend_title: "Container",
      y_title: "Mbit/s",
      stack: true,
      query: %( (
        sum by (containerName) (label_replace(rate(docker_network_received_bytes%{filter}[%{range}]), "containerName", "$1 / RX", "containerName", "(.+)"))
        or
        sum by (containerName) (label_replace(rate(docker_network_transmit_bytes%{filter}[%{range}]), "containerName", "$1 / TX", "containerName", "(.+)"))
      ) * 8 / 1000000 )
    },

    # Disk used by each volume of one app, in GB, one stacked band per volume.
    #
    # docker_volume_size is a GAUGE (current bytes), so it takes avg_over_time to smooth a
    # point, never rate. Bytes / 1e9 is decimal GB, matching how disk sizes are quoted.
    #
    # Volumes are not containers, so the custom dc_* labels the exporter adds to containers may
    # not be present here. If %{filter} matches nothing, the app selector is unavailable for
    # volumes and this chart has to be scoped another way (by the compose project prefix in the
    # volume name, or by a name label the exporter provides).
    "app_disk" => {
      context: :app,
      title: "charts.disk",
      kind: :dynamic,
      color_field: "series",
      # volumeName is the volume label; it is posted into "series", which is what the chart
      # colours and stacks by.
      series_label: "volumeName",
      legend_title: "Volume",
      y_title: "GB",
      stack: true,
      query: %( sum by (volumeName) (avg_over_time(docker_volume_size%{filter}[%{range}])) / 1000000000 )
    }
  }.freeze
end
