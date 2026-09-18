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
    def job_log(id:, instance_id:, offset: 0)
      record(:job_log, id: id, instance_id: instance_id, offset: offset)
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

  test "the default-constructed adapter routes mocked methods to the mock" do
    adapter = DcommsAdapter.new

    # catalog_entry is mocked; it must not reach the (unreachable, in tests) socket, and it
    # must not blow up on a nil mock. It returns a decorated entry from the mock fixtures.
    assert_equal "peertube", adapter.catalog_entry(id: "peertube").id
  end

  ##
  ## the documented split
  ##

  test "MOCKED lists exactly the methods the backend does not implement" do
    # Deliberately exhaustive: this list shrinking is the signal that the daemon landed
    # something. Re-verified against the Go source -- `inst/list`, `job/list`, `job/log` and
    # `job/status` (`statusByID`) are all implemented now, leaving only the absent catalog
    # detail method.
    assert_equal %i[catalog_entry].sort, DcommsAdapter::MOCKED.sort
  end

  test "the newly-implemented methods are real, not mocked" do
    # Regression guard: these were mocked while the daemon lacked them. If one slips back
    # into MOCKED, Dawa would silently stop talking to a backend that works.
    assert_equal :from_client, @adapter.job_log(id: "j", instance_id: "i")
    assert_equal :from_client, @adapter.job_list
    assert_equal :from_client, @adapter.job_status(id: "j")
    assert_equal :from_client, @adapter.apps_installed_list

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

  test "mocked methods go to the mock, not the client" do
    assert_equal :from_mock, @adapter.catalog_entry(id: "peertube")
    assert_equal [ [ :catalog_entry, { id: "peertube" } ] ], @mock.calls
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

  test "job_log forwards both identifiers and the offset" do
    # Real now, so it reaches the client rather than the mock -- but the routing is what is
    # under test here, and both identifiers must travel because the daemon keys its job map
    # on the pair.
    @adapter.job_log(id: "j", instance_id: "inst-1", offset: 128)

    assert_equal [ [ :job_log, { id: "j", instance_id: "inst-1", offset: 128 } ] ], @client.calls
  end

  test "job_log defaults the offset" do
    @adapter.job_log(id: "j", instance_id: "inst-1")

    assert_equal [ [ :job_log, { id: "j", instance_id: "inst-1", offset: 0 } ] ], @client.calls
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
      assert_equal :from_client, adapter.job_log(id: "j", instance_id: "i")
    end
  end

  test "an empty setting falls back to the default" do
    with_use_mocks("") do
      adapter = DcommsAdapter.new(client: @client, mock: @mock)

      assert_equal DcommsAdapter::MOCKED.sort, adapter.mocked_methods.sort
    end
  end

  test "mocked? answers per method" do
    assert @adapter.mocked?(:catalog_entry)
    assert @adapter.mocked?("catalog_entry")
    refute @adapter.mocked?(:catalog_list)
    refute @adapter.mocked?(:install)
    # These four were mocked while the daemon lacked them; job/status was the last to land.
    refute @adapter.mocked?(:job_log)
    refute @adapter.mocked?(:job_list)
    refute @adapter.mocked?(:job_status)
    refute @adapter.mocked?(:apps_installed_list)
  end

  #
  # catalog entry detail
  #

  test "catalog_entry is mocked until the backend exposes a detail method" do
    # Note the asymmetry: catalog_list is REAL, catalog_entry is mocked. The show page
    # therefore mixes real and fake data, which is why every detail field it renders must
    # be treated as optional.
    assert @adapter.mocked?(:catalog_entry)
    assert_equal :from_mock, @adapter.catalog_entry(id: "peertube")
  end

  test "catalog_entry goes to the client once unmocked" do
    with_use_mocks("none") do
      adapter = DcommsAdapter.new(client: @client, mock: @mock)

      assert_equal :from_client, adapter.catalog_entry(id: "peertube")
      assert_equal [ [ :catalog_entry, { id: "peertube" } ] ], @client.calls
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
