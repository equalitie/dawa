require "test_helper"

#
# Tests for ChartsComponent: the Stimulus wrapper and one `.chart` element per slot.
#
# The component nests via `v`, so it is rendered through a ComponentFactory rather than with
# `render_inline` (which leaves the factory nil).
#
class ChartsComponentTest < ActionView::TestCase
  def setup
    # ActionView::TestCase is itself a view context, which is what the factory wants.
    @factory = RaftComponents::ComponentFactory.new(self)
  end

  def render_charts(controller: "metrics", url: "/m.json", interval: nil, height: nil, charts: {})
    args = { controller: controller, url: url, interval: interval }
    args[:height] = height if height
    html = @factory.charts(**args) do |c|
      charts.each { |key, spec| c.with_chart(key, spec) }
    end
    Nokogiri::HTML.fragment(html.to_s)
  end

  test "the wrapper is the Stimulus controller with its url and interval values" do
    doc = render_charts(url: "/metrics/data.json?window=day", interval: 60_000)
    wrapper = doc.at_css("[data-controller='metrics']")

    refute_nil wrapper
    assert_equal "/metrics/data.json?window=day", wrapper["data-metrics-url-value"]
    assert_equal "60000", wrapper["data-metrics-interval-value"]
  end

  test "a nil interval omits the value so the controller's default applies" do
    doc = render_charts(interval: nil)

    assert_nil doc.at_css("[data-controller='metrics']")["data-metrics-interval-value"]
  end

  test "one chart element per slot, in the order given" do
    doc = render_charts(charts: { "host_cpu" => { title: "CPU" }, "host_memory" => { title: "Memory" } })

    keys = doc.css(".chart").map { |el| el["data-chart-key"] }
    assert_equal %w[host_cpu host_memory], keys
  end

  test "each chart carries the controller's target name, its key and its spec as JSON" do
    doc = render_charts(charts: { "host_cpu" => { title: "charts.cpu" } })
    chart = doc.at_css(".chart")

    assert_equal "chart", chart["data-metrics-target"]
    assert_equal "host_cpu", chart["data-chart-key"]
    assert_equal({ "title" => "CPU" }, JSON.parse(chart["data-chart-spec"]))
  end

  test "the chart body is the element the JS mounts into" do
    doc = render_charts(charts: { "host_cpu" => {} })

    assert_equal 1, doc.css(".chart-body[data-chart-body]").size
  end

  test "the chart body carries a placeholder until the chart is embedded" do
    doc = render_charts(charts: { "host_cpu" => {} })
    body = doc.at_css(".chart-body")

    # It has to be inside the body: vegaEmbed mounts into that element and replaces its
    # children, which is what removes the placeholder. Anywhere else would need cleanup code.
    placeholder = body.at_css(".chart-placeholder")
    refute_nil placeholder, "expected a placeholder inside the chart body"
  end

  test "the controller name drives the attribute names" do
    # The container stats panel uses the same markup with a different controller; the data
    # attributes have to follow that name or Stimulus will not find its values or targets.
    doc = render_charts(controller: "container-stats", url: "/stats.json", interval: 1500,
                        charts: { "cpu" => {} })

    wrapper = doc.at_css("[data-controller='container-stats']")
    assert_equal "/stats.json", wrapper["data-container-stats-url-value"]
    assert_equal "1500", wrapper["data-container-stats-interval-value"]

    chart = doc.at_css(".chart")
    assert_equal "chart", chart["data-container-stats-target"]
    assert_nil chart["data-metrics-target"]
  end

  test "height sets the chart body's style" do
    doc = render_charts(charts: { "host_cpu" => {} }, height: "300px")

    assert_match(/height: 300px/, doc.at_css(".chart-body")["style"])
  end

  test "no charts renders an empty wrapper rather than failing" do
    doc = render_charts(charts: {})

    refute_nil doc.at_css("[data-controller='metrics']")
    assert_empty doc.css(".chart")
  end
end
