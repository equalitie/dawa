require "test_helper"

#
# Tests for the dcommsctl adapter -- the seam that decides whether a call goes to the
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

    def catalog_list = record(:catalog_list)
    def catalog_entry(id:) = record(:catalog_entry, id: id)
    def apps_list = record(:apps_list)
    def apps_installed_list = record(:apps_installed_list)
    def install(name:, domain:) = record(:install, name: name, domain: domain)
    def uninstall(id:) = record(:uninstall, id: id)
    def start(id:) = record(:start, id: id)
    def stop(id:) = record(:stop, id: id)
    def backup(id:) = record(:backup, id: id)
    def restore(id:) = record(:restore, id: id)
    def job_status(id:) = record(:job_status, id: id)
    def job_log(id:, offset: 0)
      record(:job_log, id: id, offset: offset)
    end
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

  ##
  ## construction
  ##

  test "a default-constructed adapter has real collaborators, not nil" do
    # Controllers call DcommsAdapter.new with no arguments. If the collaborators defaulted to
    # nil, every request would raise "undefined method ... for nil" rather than reaching the
    # backend. Tests that always inject stubs cannot catch that, so assert it directly.
    adapter = DcommsAdapter.new

    assert_instance_of DcommsClient, adapter.client
    assert_instance_of DcommsMock, adapter.mock
  end

  test "the default-constructed adapter talks to the real client" do
    # Nothing is mocked by default any more, so `catalog_entry` must reach the client rather
    # than the mock. Asserting that it RAISES ConnectionError (as this once did) only holds
    # on a machine with no daemon: where dcommsctl runs, the call succeeds and the test
    # fails. So the socket layer is stubbed instead of relying on the network being down,
    # which proves the routing deterministically either way.
    adapter = DcommsAdapter.new
    sent = []
    adapter.client.define_singleton_method(:call) do |method, params = nil|
      sent << [ method, params ]
      { "id" => "peertube", "name" => "Peertube" }
    end

    entry = adapter.catalog_entry(id: "peertube")

    assert_equal "peertube", entry.id
    assert_equal [ [ "app/get", { id: "peertube" } ] ], sent
  end

  ##
  ## the documented split
  ##

  test "MOCKED is empty, because the daemon implements everything Dawa calls" do
    # Deliberately exhaustive: this list shrinking is the signal that the daemon landed
    # something. The last holdout was the catalog detail -- `app/get` (rpc_app_get.go) now
    # returns a full ApplicationDetail, so nothing needs faking.
    assert_empty DcommsAdapter::MOCKED
  end

  test "every method the daemon implements is real, not mocked" do
    # Regression guard: each of these was mocked at some point while the daemon lacked it. If
    # one slips back into MOCKED, Dawa would silently stop talking to a backend that works.
    assert_equal :from_client, @adapter.job_log(id: "j")
    assert_equal :from_client, @adapter.job_list
    assert_equal :from_client, @adapter.job_status(id: "j")
    assert_equal :from_client, @adapter.apps_installed_list
    assert_equal :from_client, @adapter.catalog_entry(id: "peertube")

    assert_empty @mock.calls
  end

  test "REAL and MOCKED do not overlap" do
    assert_empty DcommsAdapter::REAL & DcommsAdapter::MOCKED
  end

  # Deprecated aliases, kept for compatibility while the vocabulary settles. Each should
  # disappear once nothing calls them.
  DEPRECATED_ALIASES = %i[definitions_list apps_list instances_list].freeze

  test "every method on the adapter is classified as real or mocked" do
    adapter_methods = DcommsAdapter.public_instance_methods(false)
    classified = DcommsAdapter::REAL + DcommsAdapter::MOCKED
    # methods that are not RPC calls (routing helpers) are exempt, as are deprecated aliases
    unclassified = adapter_methods - classified - %i[mocked? mocked_methods client mock] - DEPRECATED_ALIASES

    assert_empty unclassified, "unclassified adapter methods: #{unclassified.inspect}"
  end

  test "the deprecated aliases still route like their replacements" do
    assert_equal :from_client, @adapter.definitions_list
    assert_equal [ [ :catalog_list, {} ] ], @client.calls

    # apps_installed_list is real now (inst/list is implemented), so its alias takes the
    # real path too. The point is that the alias routes where its replacement does.
    assert_equal :from_client, @adapter.instances_list
    assert_includes @client.calls, [ :apps_installed_list, {} ]
  end

  test "the default configuration mocks exactly MOCKED" do
    assert_equal DcommsAdapter::MOCKED.sort, @adapter.mocked_methods.sort
  end

  ##
  ## routing
  ##

  test "real methods go to the client, not the mock" do
    assert_equal :from_client, @adapter.catalog_list
    assert_equal [ [ :catalog_list, {} ] ], @client.calls
    assert_empty @mock.calls
  end

  test "a method routed to the mock does not reach the client" do
    # No method is mocked by default, so the mock branch is reached through configuration.
    # That branch has to keep working: it is how `dcomms_use_mocks` serves the app offline.
    with_use_mocks("catalog_entry") do
      adapter = DcommsAdapter.new(client: @client, mock: @mock)

      assert_equal :from_mock, adapter.catalog_entry(id: "peertube")
      assert_equal [ [ :catalog_entry, { id: "peertube" } ] ], @mock.calls
      assert_empty @client.calls
    end
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

  test "job_log forwards the job id and the offset" do
    # Real now, so it reaches the client rather than the mock -- but the routing is what is
    # under test here, and both identifiers must travel because the daemon keys its job map
    # on the pair.
    @adapter.job_log(id: "j", offset: 128)

    assert_equal [ [ :job_log, { id: "j", offset: 128 } ] ], @client.calls
  end

  test "job_log defaults the offset" do
    @adapter.job_log(id: "j")

    assert_equal [ [ :job_log, { id: "j", offset: 0 } ] ], @client.calls
  end

  test "job_list forwards its filters" do
    @adapter.job_list(instance_id: "inst-1", active_only: true)

    assert_equal [ [ :job_list, { instance_id: "inst-1", active_only: true } ] ], @client.calls
  end

  ##
  ## configuration
  ##

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

      assert_equal :from_mock, adapter.catalog_list
      assert_empty @client.calls
    end
  end

  test "use_mocks accepts an explicit list" do
    with_use_mocks("job_status, catalog_list") do
      adapter = DcommsAdapter.new(client: @client, mock: @mock)

      assert_equal %i[catalog_list job_status].sort, adapter.mocked_methods.sort
      assert_equal :from_mock, adapter.catalog_list
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
    # Nothing is mocked by default, so every method answers false...
    refute @adapter.mocked?(:catalog_entry)
    refute @adapter.mocked?(:catalog_list)
    refute @adapter.mocked?(:install)
    refute @adapter.mocked?(:job_log)
    refute @adapter.mocked?(:job_list)
    refute @adapter.mocked?(:job_status)
    refute @adapter.mocked?(:apps_installed_list)

    # ...and `mocked?` still works when the configuration turns one back on.
    with_use_mocks("catalog_entry") do
      configured = DcommsAdapter.new(client: @client, mock: @mock)

      assert configured.mocked?(:catalog_entry)
      assert configured.mocked?("catalog_entry")
      refute configured.mocked?(:catalog_list)
    end
  end

  #
  # catalog entry detail
  #

  test "catalog_entry is real now that app/get exists" do
    # `app/get` (rpc_app_get.go) returns a full ApplicationDetail, so the old asymmetry with
    # catalog_list (real list, faked detail) is gone. The view still treats every detail
    # field as optional, because the daemon omits empty ones.
    refute @adapter.mocked?(:catalog_entry)
    assert_equal :from_client, @adapter.catalog_entry(id: "peertube")
  end

  test "catalog_entry can still be served from the mock when configured to" do
    with_use_mocks("catalog_entry") do
      adapter = DcommsAdapter.new(client: @client, mock: @mock)

      assert_equal :from_mock, adapter.catalog_entry(id: "peertube")
      assert_equal [ [ :catalog_entry, { id: "peertube" } ] ], @mock.calls
      assert_empty @client.calls
    end
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
