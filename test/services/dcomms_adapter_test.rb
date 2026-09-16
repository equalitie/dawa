require "test_helper"

#
# Tests for the dcommsctl adapter — the seam that decides whether a call goes to the
# real backend or to DcommsMock.
#
# The two things worth pinning: the routing is exactly the documented split (so a method
# that starts working cannot stay silently mocked), and the configuration override works
# (so unmocking is a config change, not a code change).
#
class DcommsAdapterTest < ActiveSupport::TestCase
  # Records which calls it received, so we can assert routing without a socket.
  class Spy
    attr_reader :calls

    def initialize(return_value: :spy_result)
      @calls = []
      @return_value = return_value
    end

    def apps_list = record(:apps_list)
    def instances_list = record(:instances_list)
    def install(name:, domain:) = record(:install, name: name, domain: domain)
    def uninstall(id:) = record(:uninstall, id: id)
    def start(id:) = record(:start, id: id)
    def stop(id:) = record(:stop, id: id)
    def backup(id:) = record(:backup, id: id)
    def restore(id:) = record(:restore, id: id)
    def job_status(id:) = record(:job_status, id: id)
    def job_log(id:, offset: 0) = record(:job_log, id: id, offset: offset)
    def job_list(instance_id: nil, active_only: false)
      record(:job_list, instance_id: instance_id, active_only: active_only)
    end

    private

    def record(name, **args)
      @calls << [ name, args ]
      @return_value
    end
  end

  setup do
    @client = Spy.new(return_value: :from_client)
    @mock = Spy.new(return_value: :from_mock)
    @adapter = DcommsAdapter.new(client: @client, mock: @mock)
  end

  # --- the documented split ----------------------------------------------

  test "MOCKED lists exactly the methods the backend does not implement" do
    assert_equal %i[job_status job_log job_list instances_list].sort, DcommsAdapter::MOCKED.sort
  end

  test "REAL and MOCKED do not overlap" do
    assert_empty DcommsAdapter::REAL & DcommsAdapter::MOCKED
  end

  test "every method on the adapter is classified as real or mocked" do
    adapter_methods = DcommsAdapter.public_instance_methods(false)
    classified = DcommsAdapter::REAL + DcommsAdapter::MOCKED
    # methods that are not RPC calls (routing helpers) are exempt
    unclassified = adapter_methods - classified - %i[mocked? mocked_methods client mock]

    assert_empty unclassified, "unclassified adapter methods: #{unclassified.inspect}"
  end

  test "the default configuration mocks exactly MOCKED" do
    assert_equal DcommsAdapter::MOCKED.sort, @adapter.mocked_methods.sort
  end

  # --- routing -----------------------------------------------------------

  test "real methods go to the client, not the mock" do
    assert_equal :from_client, @adapter.apps_list
    assert_equal [ [ :apps_list, {} ] ], @client.calls
    assert_empty @mock.calls
  end

  test "mocked methods go to the mock, not the client" do
    assert_equal :from_mock, @adapter.job_status(id: "j")
    assert_equal [ [ :job_status, { id: "j" } ] ], @mock.calls
    assert_empty @client.calls
  end

  test "mutations that work today are real" do
    assert_equal :from_client, @adapter.start(id: "inst-1")

    assert_equal [ [ :start, { id: "inst-1" } ] ], @client.calls
    assert_empty @mock.calls
  end

  test "install forwards both keywords to the real client" do
    @adapter.install(name: "peertube", domain: "pt.test")

    assert_equal [ [ :install, { name: "peertube", domain: "pt.test" } ] ], @client.calls
  end

  test "job_log forwards the offset" do
    @adapter.job_log(id: "j", offset: 128)

    assert_equal [ [ :job_log, { id: "j", offset: 128 } ] ], @mock.calls
  end

  test "job_log defaults the offset" do
    @adapter.job_log(id: "j")

    assert_equal [ [ :job_log, { id: "j", offset: 0 } ] ], @mock.calls
  end

  test "job_list forwards its filters" do
    @adapter.job_list(instance_id: "inst-1", active_only: true)

    assert_equal [ [ :job_list, { instance_id: "inst-1", active_only: true } ] ], @mock.calls
  end

  # --- configuration -----------------------------------------------------

  test "use_mocks none sends everything to the client" do
    with_use_mocks("none") do
      adapter = DcommsAdapter.new(client: @client, mock: @mock)

      assert_empty adapter.mocked_methods
      assert_equal :from_client, adapter.job_status(id: "j")
      assert_empty @mock.calls
    end
  end

  test "use_mocks all sends everything to the mock" do
    with_use_mocks("all") do
      adapter = DcommsAdapter.new(client: @client, mock: @mock)

      assert_equal :from_mock, adapter.apps_list
      assert_empty @client.calls
    end
  end

  test "use_mocks accepts an explicit list" do
    with_use_mocks("job_status, apps_list") do
      adapter = DcommsAdapter.new(client: @client, mock: @mock)

      assert_equal %i[apps_list job_status].sort, adapter.mocked_methods.sort
      assert_equal :from_mock, adapter.apps_list
      assert_equal :from_client, adapter.job_log(id: "j")
    end
  end

  test "an empty setting falls back to the default" do
    with_use_mocks("") do
      adapter = DcommsAdapter.new(client: @client, mock: @mock)

      assert_equal DcommsAdapter::MOCKED.sort, adapter.mocked_methods.sort
    end
  end

  test "mocked? answers per method" do
    assert @adapter.mocked?(:job_status)
    assert @adapter.mocked?("instances_list")
    refute @adapter.mocked?(:apps_list)
    refute @adapter.mocked?(:install)
  end

  private

  # Conf values are read at call time, so we can swap the configured string.
  def with_use_mocks(value)
    prior = Conf.dcomms_use_mocks
    Conf.define_singleton_method(:dcomms_use_mocks) { value }
    yield
  ensure
    if prior
      Conf.define_singleton_method(:dcomms_use_mocks) { prior }
    else
      Conf.singleton_class.send(:remove_method, :dcomms_use_mocks) if Conf.respond_to?(:dcomms_use_mocks)
    end
  end
end
