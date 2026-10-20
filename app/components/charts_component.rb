#
# A streaming victoriametrics + vega chart panel.
# Depends on metrics_controller.js
#
#   = v.charts(url: data_metrics_path(format: :json, window: "day"), interval: 60_000) do |c|
#     - @metrics_charts.each do |key, spec|
#       - c.with_chart(key, spec)
#
# Renders a Stimulus container plus one `.chart` element per chart slot, each carrying the
# chart's key, its Vega-Lite spec (as JSON), and a `.chart-body` for the JS to mount into.
#
# This defaults to using the metrics stimulus controller.
# See ChartsContainerComponent for container charts.
#
class ChartsComponent < ApplicationComponent
  DEFAULT_HEIGHT = 200

  renders_many :charts, ->(key, spec) do
    spec = spec.dup()
    spec[:title] = t(spec[:title])
    tag.div(class: "chart mb-3", data: chart_data(key, spec)) do
      tag.div(class: "chart-body w-100", data: { chart_body: true }, style: body_style) do
        placeholder(spec[:title])
      end
    end
  end

  haml_template <<~HAML
    %div{data: controller_data}
      - charts.each do |chart|
        = chart
  HAML

  def initialize(url:, controller: nil, target: "chart", interval: nil, height: DEFAULT_HEIGHT, **args)
    super(**args)
    @controller = controller
    @target = target
    @url = url
    @interval = interval
    @height = height.to_i
  end

  private

  def controller_data
    data = {
      controller: stimulus_controller_name,
      "#{stimulus_controller_name}-url-value": @url
    }
    data[:"#{stimulus_controller_name}-interval-value"] = @interval if @interval
    data.merge(@data)
  end

  def chart_data(key, spec)
    {
      "#{stimulus_controller_name}-target": @target,
      chart_key: key,
      chart_spec: spec.to_json
    }
  end

  def stimulus_controller_name
    @controller || "metrics"
  end

  def body_style = "height: #{@height}px;"

  #
  # this is a crude approximation of the svg that vega generates.
  #
  def placeholder(title)
    tag.div(class: "chart-placeholder d-flex flex-column", style: "height: #{@height}px; margin: 2px 6px 0 45px") do
      safe_join([
        tag.div(class: "fw-bold text-center", style: "font-size: 85%; margin-bottom: 30px") { title },
        tag.div(class: "d-flex-grow-1 border shaded", style: "height: #{@height-76}px")
      ])
    end
  end
end
