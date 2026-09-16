#
# Shared helpers for building Vega-Lite area chart specifications backed by a
# single streaming "chartdata" dataset.
#
# Both container resource graphs (ContainerStatsHelper) and future
# VictoriaMetrics host graphs reuse these builders, so chart output stays
# consistent and data streaming (view.change("chartdata", changeset)) works the
# same everywhere.
#
# Charts are layered: an area mark for the trend, plus an invisible circle
# layer that shows a tooltip with the data point's details on hover.
#
module VegaChartHelper
  #
  # Build a single-series area chart spec (one y value per point), e.g. CPU%.
  # Pass an optional vega.rb `transform` (calculate) to derive the y field, and
  # optionally a `data_name` (default "chartdata") matching the dataset the
  # client streams via view.change(data_name, ...).
  #
  def vega_area_spec(points, title:, y_field:, y_title:, color:, tooltip:, transform: nil, data_name: "chartdata", time_domain: nil)
    chart = Vega.lite
      .data(name: data_name, values: points)
      .width("container")
      .height(120)
      .autosize(streaming_autosize)
      .title(title)
      .encoding(
        x: x_encoding(time_domain),
        y: { field: y_field, type: "quantitative", title: y_title }
      )
    chart = chart.transform(transform) if transform
    chart.layer(area_marks(interpolate: "monotone", color: color, opacity: 0.6).push(
      hover_tooltip_layer(tooltip)
    )).spec
  end

  #
  # Build an area chart whose series are folded from two point fields
  # (e.g. net_rx/net_tx) into a nominal direction, then colored by direction.
  # `fold` is the pair of point fields to fold; `label_calc` maps the folded
  # direction field to a friendly label (e.g. "datum.direction == 'net_rx' ? 'RX' : 'TX'").
  # Both a bytes->MB/s calculation and the direction label are applied internally.
  #
  def vega_folded_area_spec(points, title:, fold:, label_calc:, y_title:, domain:, range:, tooltip:, data_name: "chartdata", time_domain: nil)
    fold_transform = { fold: fold, as: [ "direction", "bytes" ] }
    transforms = [
      { calculate: "datum.bytes / 1048576", as: "mbps" },
      { calculate: label_calc, as: "direction_label" }
    ]
    Vega.lite
      .data(name: data_name, values: points)
      .width("container")
      .height(120)
      .autosize(streaming_autosize)
      .title(title)
      .transform([ fold_transform ] + transforms)
      .encoding(
        x: x_encoding(time_domain),
        y: { field: "mbps", type: "quantitative", title: y_title },
        color: { field: "direction", type: "nominal", title: nil,
                 scale: { domain: domain, range: range },
                 legend: { orient: "top" } }
      )
      .layer([
        { mark: { type: "area", interpolate: "monotone", opacity: 0.5 } },
        hover_tooltip_layer(tooltip)
      ])
      .spec
  end

  #
  # Build an area chart colored by an existing nominal series field (e.g.
  # "series") where each row is already tagged, rather than folded from two
  # fields. Used for charts that combine the results of multiple queries.
  #
  def vega_series_area_spec(points, title:, y_field:, y_title:, color_field:, domain:, range:, tooltip:, data_name: "chartdata", opacity: 0.5, stack: true, time_domain: nil, mark: :area)
    y_encoding = { field: y_field, type: "quantitative", title: y_title }
    # Make stacking explicit so the stacked y scale is shared by the series mark AND
    # the separate hover-circle layer. Relying on inference (no stack key) left the
    # hover circle at the unstacked position on the stacked charts.
    y_encoding[:stack] = stack ? "zero" : false
    Vega.lite
      .data(name: data_name, values: points)
      .width("container")
      .height(120)
      .autosize(streaming_autosize)
      .title(title)
      .encoding(
        x: x_encoding(time_domain),
        y: y_encoding,
        color: { field: color_field, type: "nominal", title: nil,
                 scale: { domain: domain, range: range },
                 legend: { orient: "top" } }
      )
      .layer([ series_mark(mark, opacity), hover_tooltip_layer(tooltip, y: y_encoding) ])
      .spec
  end

  private

  #
  # Shared time (x) axis encoding. An optional explicit time_domain ([start_ms,
  # end_ms]) fixes the visible x extent to the full requested window, so a chart
  # whose data only covers part of the window (e.g. metrics retained for one day
  # but a one-month window requested) still spans the whole window. Without it,
  # Vega derives the domain from the data and the chart shrinks to just the data.
  #
  def x_encoding(time_domain = nil)
    enc = { field: "time", type: "temporal", axis: x_axis_config }
    enc[:scale] = { domain: time_domain } if time_domain
    enc
  end

  #
  # Axis config for the shared time (x) axis. A fixed tickCount keeps the number
  # of labels small even when the chart renders very wide (where Vega-Lite would
  # otherwise add too many labels that crowd and bleed together), and
  # labelOverlap:"greedy" guarantees no two labels ever collide, regardless of
  # label width or chart width.
  #
  # labelOverlap uses Vega's axis label overlap handling:
  # https://vega.github.io/vega/docs/axes/#labelOverlap
  #
  def x_axis_config
    { title: nil, tickCount: 8, labelOverlap: "greedy" }
  end

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
  # The base series mark layer for multi-series charts. Defaults to filled area
  # marks (monotone interpolation, optional opacity), but can render plain line
  # marks (no fill) when :line, e.g. for disk capacity/used/free where stacked
  # areas overlap and hide each other.
  #
  def series_mark(mark, opacity)
    if mark.to_sym == :line
      { mark: { type: "line", interpolate: "monotone" } }
    else
      { mark: { type: "area", interpolate: "monotone", opacity: opacity } }
    end
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
  def hover_tooltip_layer(tooltip = true, y: nil)
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
    # Tie the hover circle to the same y encoding as the series marks. For stacked
    # charts the series layer sets stack on its y channel; without the same y here
    # the circle resolves at the unstacked position and the tooltip no longer hugs
    # the (stacked) line/area it belongs to.
    layer[:encoding][:y] = y if y
    layer[:encoding][:tooltip] = tooltip if tooltip.is_a?(Array)
    layer
  end
end
