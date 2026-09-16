require_relative "../test_helper"

#
# Controller tests for the troubleshoot page's VictoriaMetrics diagnostic.
# The VictoriaMetrics gem client is stubbed so these run without a live instance.
#
class TroubleshootControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(username: "troubleshoot-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
  end

  def with_service_client(fake)
    original = VictoriaMetrics.instance_method(:client)
    VictoriaMetrics.send(:define_method, :client) { fake }
    yield
  ensure
    VictoriaMetrics.send(:define_method, :client, original)
  end

  def client_returning(query_result)
    fake = Object.new
    fake.define_singleton_method(:query) { |**_kw| query_result }
    fake.define_singleton_method(:query_range) { |**_kw| { "resultType" => "matrix", "result" => [] } }
    fake
  end

  def client_raising
    fake = Object.new
    fake.define_singleton_method(:query) do |**_kw|
      raise Prometheus::ApiClient::Client::RequestError, "connection refused"
    end
    fake.define_singleton_method(:query_range) { |**_kw| [] }
    fake
  end

  def test_show_renders_provider_list_when_up_returns_instances
    result = {
      "resultType" => "vector",
      "result" => [
        { "metric" => { "instance" => "host-a.example", "job" => "node" }, "value" => [ 1_787_518_080.0, "1" ] },
        { "metric" => { "instance" => "host-b.example", "job" => "node" }, "value" => [ 1_787_518_080.0, "0" ] }
      ]
    }

    with_service_client(client_returning(result)) do
      login_as(@user)
      get troubleshoot_path
    end

    assert_response :success
    assert_select ".alert-success", text: /Connected/
    assert_select "code", text: "host-a.example"
    assert_select "code", text: "host-b.example"
    # one up badge and one down badge
    assert_select ".badge.text-bg-success", text: "up"
    assert_select ".badge.text-bg-danger", text: "down"
  end

  def test_show_reports_unreachable_when_query_raises
    with_service_client(client_raising) do
      login_as(@user)
      get troubleshoot_path
    end

    assert_response :success
    assert_select ".alert-danger", text: /Unreachable/
    assert_select ".alert-danger", text: /connection refused/
  end

  def test_show_reports_connected_but_no_result
    with_service_client(client_returning({ "resultType" => "vector", "result" => [] })) do
      login_as(@user)
      get troubleshoot_path
    end

    assert_response :success
    assert_select ".alert-danger", text: /Metrics Providers None/
  end
end
