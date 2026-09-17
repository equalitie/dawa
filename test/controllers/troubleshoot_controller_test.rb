require_relative "../test_helper"

#
# Controller tests for the troubleshoot page's backend diagnostics.
#
# Every backend is stubbed: these run without a live VictoriaMetrics, VictoriaLogs, Docker
# daemon or dcommsctl. What matters here is the page's contract -- each check renders its
# own verdict, one backend being down does not hide the others, and no check turns an
# unreachable service into a 500.
#
class TroubleshootControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(username: "troubleshoot-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
    # Default every backend to "reachable" so each test only has to arrange the one it is
    # about. Without this, an un-stubbed Docker/Logs/dcommsctl call would hit the network.
    stub_checks
  end

  ##
  ## stubbing
  ##

  # Stub the controller's four diagnostics. Only the keyword given changes its default.
  #
  # The real methods are aliased aside here and restored in `teardown`. They must not be
  # `remove_method`d: that drops the controller's own method for the rest of the process,
  # and any later test then fails with a baffling "undefined local variable or method".
  def stub_checks(vm: :ok, vl: :ok, docker: :ok, dcomms: :ok)
    stubs = {
      vm_diagnostic: vm_diagnostic_result(vm),
      vl_diagnostic: vl_diagnostic_result(vl),
      docker_diagnostic: docker_diagnostic_result(docker),
      dcomms_diagnostic: dcomms_diagnostic_result(dcomms)
    }

    stubs.each do |name, value|
      # Only capture the original once per test. `stub_checks` can be called more than once
      # (setup, then a test narrowing one backend), and re-aliasing would make
      # `<name>_without_stub` point at the previous stub.
      unless TroubleshootController.method_defined?(:"#{name}_without_stub")
        TroubleshootController.alias_method(:"#{name}_without_stub", name)
      end

      TroubleshootController.define_method(name) { value }
    end
  end

  def teardown
    return unless TroubleshootController.method_defined?(:vm_diagnostic_without_stub)

    %i[vm_diagnostic vl_diagnostic docker_diagnostic dcomms_diagnostic].each do |name|
      TroubleshootController.alias_method(name, :"#{name}_without_stub")
      TroubleshootController.send(:remove_method, :"#{name}_without_stub")
    end
  end

  # A VM result is either :ok, :empty (reachable, no `up` series), or :down.
  def vm_diagnostic_result(kind)
    case kind
    when :empty
      { connected: true, query_ok: false, error: nil, providers: [] }
    when :down
      { connected: false, query_ok: false, error: "connection refused", providers: [] }
    else
      {
        connected: true,
        query_ok: true,
        error: nil,
        providers: [
          { instance: "host-a.example", job: "node", up: true },
          { instance: "host-b.example", job: "node", up: false }
        ]
      }
    end
  end

  def vl_diagnostic_result(kind)
    case kind
    when :empty then { connected: true, field_count: 0, error: nil }
    when :down then { connected: false, field_count: 0, error: "logs refused" }
    else { connected: true, field_count: 4, error: nil }
    end
  end

  def docker_diagnostic_result(kind)
    case kind
    when :down
      { connected: false, version: nil, api_version: nil, error: "Could not connect to Docker: socket" }
    else
      { connected: true, version: "27.3.1", api_version: "1.47", error: nil }
    end
  end

  def dcomms_diagnostic_result(kind)
    case kind
    when :down then { connected: false, job_count: 0, error: "daemon refused" }
    else { connected: true, job_count: 3, error: nil }
    end
  end

  def get_troubleshoot
    login_as(@user)
    get troubleshoot_path
  end

  ##
  ## VictoriaMetrics (existing behaviour, kept)
  ##

  def test_show_renders_provider_list_when_up_returns_instances
    get_troubleshoot

    assert_response :success
    assert_select "code", text: Conf.metrics_url
    assert_select "code", text: "host-a.example"
    assert_select "code", text: "host-b.example"
    # one up badge and one down badge
    assert_select ".badge.text-bg-success", text: "up"
    assert_select ".badge.text-bg-danger", text: "down"
  end

  def test_show_reports_vm_unreachable
    stub_checks(vm: :down)
    get_troubleshoot

    assert_response :success
    assert_select "code", text: Conf.metrics_url
    assert_select ".alert-danger", text: /connection refused/
  end

  def test_show_reports_vm_connected_but_no_result
    stub_checks(vm: :empty)
    get_troubleshoot

    assert_response :success
    # reachable with no `up` series is not an unreachable backend
    assert_select ".alert-danger", text: /Metrics Providers None/
  end

  ##
  ## VictoriaLogs
  ##

  test "the victorialogs probe sends a query, because a bare field_names call is rejected" do
    # Regression guard: VictoriaLogs answers 400 to /select/logsql/field_names with no
    # `query` arg at all, so the diagnostic must pass one. Called on a plain instance via
    # `send`, with `setup`'s stubbed diagnostic bypassed by unpicking that one method.
    requested = []
    fake = Object.new
    fake.define_singleton_method(:field_names) do |query = nil|
      requested << query
      [ "_msg" ]
    end

    controller = TroubleshootController.new
    controller.instance_variable_set(:@vl_service, fake)

    # `setup` aliased the real method to `vl_diagnostic_without_stub`; call it directly so
    # the canned hash is not what gets exercised.
    result = controller.send(:vl_diagnostic_without_stub)

    assert result[:connected]
    assert_equal 1, result[:field_count]
    assert_equal [ "*" ], requested, "expected the probe to pass a LogsQL query"
  end

  def test_show_reports_victorialogs_connected_with_field_count
    get_troubleshoot

    assert_response :success
    assert_select "code", text: Conf.logs_url
    assert_select ".badge.text-bg-success", text: "4"
  end

  def test_show_reports_victorialogs_with_no_fields
    stub_checks(vl: :empty)
    get_troubleshoot

    assert_response :success
    assert_select "code", text: Conf.logs_url
    # reachable but empty is a warning, not a failure: the API answered
    assert_select ".badge.text-bg-warning", text: "none"
  end

  def test_show_reports_victorialogs_unreachable
    stub_checks(vl: :down)
    get_troubleshoot

    assert_response :success
    assert_select "code", text: Conf.logs_url
    assert_select ".alert-danger", text: /logs refused/
  end

  ##
  ## Docker Engine
  ##

  def test_show_reports_docker_connected_with_versions
    get_troubleshoot

    assert_response :success
    assert_select "code", text: Conf.docker_url
    assert_select ".badge", text: "27.3.1"
    assert_select ".badge", text: "1.47"
  end

  def test_show_reports_docker_unreachable
    stub_checks(docker: :down)
    get_troubleshoot

    assert_response :success
    assert_select "code", text: Conf.docker_url
    assert_select ".alert-danger", text: /Could not connect to Docker/
  end

  ##
  ## dcommsctl
  ##

  def test_show_reports_dcomms_connected_with_job_count
    get_troubleshoot

    assert_response :success
    assert_select "code", text: Conf.dcomms_url
    assert_select ".badge", text: "3"
  end

  def test_show_reports_dcomms_unreachable
    stub_checks(dcomms: :down)
    get_troubleshoot

    assert_response :success
    assert_select "code", text: Conf.dcomms_url
    assert_select ".alert-danger", text: /daemon refused/
  end

  ##
  ## the page as a whole
  ##

  def test_show_renders_a_section_for_every_backend
    get_troubleshoot

    assert_response :success
    %w[metrics logs docker dcomms].each do |section|
      assert_select "h4", text: I18n.t("troubleshoot.#{section}")
    end
  end

  def test_show_checks_every_backend_even_when_one_is_down
    # The point of the page is to tell "one service is down" from "everything is down", so
    # a failing check must not stop the others from reporting.
    stub_checks(vm: :down)
    get_troubleshoot

    assert_response :success
    # VM reports danger; the other three still report success
    assert_select ".alert-danger", count: 1
    assert_select "code", text: Conf.logs_url
    assert_select "code", text: Conf.docker_url
    assert_select "code", text: Conf.dcomms_url
  end

  def test_show_raises_no_missing_translations
    get_troubleshoot

    assert_response :success
    # A missing key renders as "translation missing: en...."; assert none leaks to the page.
    assert_no_match(/translation missing/, response.body)
  end

  def test_show_requires_an_admin
    get troubleshoot_path

    assert_response :redirect
  end
end
