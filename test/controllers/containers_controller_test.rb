require_relative "../test_helper"
require "docker_engine_ruby"

class ContainersControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(username: "container-test-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
  end

  def test_index_renders_table_when_docker_available
    container = OpenStruct.new(id: "id-123", names: ["/web-app"], image: "nginx:latest", status: "Up 2 hours", state: :running, created: 1.hour.ago.to_i)

    stub_docker_list([container]) do
      login_as(@user)
      get containers_path
    end

    assert_response :success
    assert_select "td", text: "web-app"
    assert_select "span.badge.bg-success", text: "Running"
    assert_select "td", text: "Up 2 hours"
  end

  def test_index_handles_connection_error
    ContainersController.define_method(:docker_client) { raise DockerEngineRuby::Errors::APIConnectionError.new(url: URI.parse("http://localhost")) }

    login_as(@user)
    get containers_path

    assert_response :success
    assert_select ".alert-danger"
  ensure
    ContainersController.send(:remove_method, :docker_client)
  end

  def test_index_empty_list
    stub_docker_list([]) do
      login_as(@user)
      get containers_path
    end

    assert_response :success
  end

  def test_update_start_enqueues_job
    container_id = "start-test-1"

    login_as(@user)

    assert_enqueued_with(job: ContainerJob, args: [ container_id, "start" ]) do
      put container_path(container_id), params: { command: "start" }
    end

    assert_response :ok
  end

  def test_update_stop_enqueues_job
    container_id = "stop-test-1"

    login_as(@user)

    assert_enqueued_with(job: ContainerJob, args: [ container_id, "stop" ]) do
      put container_path(container_id), params: { command: "stop" }
    end

    assert_response :ok
  end

  def test_update_restart_enqueues_job
    container_id = "restart-test-1"

    login_as(@user)

    assert_enqueued_with(job: ContainerJob, args: [ container_id, "restart" ]) do
      put container_path(container_id), params: { command: "restart" }
    end

    assert_response :ok
  end

  def test_update_returns_ok_even_without_command
    login_as(@user)
    put container_path("any-id")

    assert_response :ok
  end

  def test_show_renders_container_details
    container_id = "abc123def456"
    container = build_container_stub(container_id)

    stub_docker_inspect(container_id, container) do
      login_as(@user)
      get container_path(container_id)
    end

    assert_response :success
    assert_select "code", text: container_id
    assert_select "td", text: "nginx:1.25"
    assert_select ".badge.bg-success", text: "Running"
  end

  def test_show_shows_exited_status
    container_id = "dead0000beef"
    container = build_container_stub(container_id, status: :exited, running: false, exit_code: 0, finished_at: "2026-07-23T10:00:00Z")

    stub_docker_inspect(container_id, container) do
      login_as(@user)
      get container_path(container_id)
    end

    assert_response :success
    assert_select ".badge.bg-secondary", text: "Exited"
  end

  def test_show_shows_error_status
    container_id = "err00000001"
    container = build_container_stub(container_id, status: :exited, running: false, exit_code: 137, finished_at: "2026-07-23T10:00:00Z")

    stub_docker_inspect(container_id, container) do
      login_as(@user)
      get container_path(container_id)
    end

    assert_response :success
    assert_select ".badge.bg-danger", text: "Exited (137)"
  end

  def test_show_has_turbo_frame_for_stats
    container_id = "stats-frame-1"
    container = build_container_stub(container_id)

    stub_docker_inspect(container_id, container) do
      login_as(@user)
      get container_path(container_id)
    end

    assert_response :success
    assert_select "turbo-frame#container-stats"
  end

  def test_stats_renders_charts_html
    container_id = "stats-test-1"
    stats_obj = build_stats_stub

    stub_docker_stats(container_id, stats_obj) do
      login_as(@user)
      get stats_container_path(container_id)
    end

    assert_response :success
    # four area chart containers, each with a streamable spec
    assert_select "[data-container-stats-target=chart]", count: 4
    assert_select "[data-chart-key=cpu]"
    assert_select "[data-chart-key=memory]"
    assert_select "[data-chart-key=network]"
    assert_select "[data-chart-key=block_io]"
    assert_select "[data-chart-spec]"
  end

  def test_stats_returns_json_payload
    container_id = "stats-json-1"
    Rails.cache.delete("container_stats_points:#{container_id}")
    Rails.cache.delete("container_stats_prev:#{container_id}")
    first = build_stats_stub
    second = build_stats_stub(net_total: 2_500_000, blk_total: 1_000_000)

    travel_to(Time.zone.now) do
      stub_docker_stats_sequence(container_id, [ first, second ]) do
        login_as(@user)

        get stats_container_path(container_id, format: :json)
        assert_response :success
        first_json = JSON.parse(response.body)
        first_sample = first_json["sample"]
        assert_equal 20.0, first_sample["cpu_pct"]
        assert_equal 50.0, first_sample["mem_pct"]
        assert_nil first_sample["net_rx"] # no previous sample yet
        assert first_sample["time"].present?
        # first poll seeds a single point
        assert_equal 1, first_json["points"].length

        # Advance time by 2s, then poll again -> rates are delta / elapsed
        travel(2.seconds)
        get stats_container_path(container_id, format: :json)
        assert_response :success
        second_json = JSON.parse(response.body)
        second_sample = second_json["sample"]

        # rx/tx delta = (2.5MB - 1MB) / 2s = 750KB/s
        assert_equal 750_000, second_sample["net_rx"]
        assert_equal 750_000, second_sample["net_tx"]
        # blk delta = (1MB - 500KB) / 2s = 250KB/s
        assert_equal 250_000, second_sample["blk_read"]
        assert_equal 250_000, second_sample["blk_write"]
        # points accumulate over time
        assert_equal 2, second_json["points"].length
        assert_equal 20.0, second_json["points"].first["cpu_pct"]
      end
    end
  end

  def test_stats_handles_unavailable
    container_id = "stats-unavail"

    ContainersController.define_method(:docker_client) do
      Object.new.tap do |c|
        c.define_singleton_method(:containers) do
          Object.new.tap do |cc|
            cc.define_singleton_method(:stats) { |id, **| raise DockerEngineRuby::Errors::APIConnectionError.new(url: URI.parse("http://localhost")) }
          end
        end
      end
    end

    login_as(@user)
    get stats_container_path(container_id)

    assert_response :success
  end

  private

  def build_stats_stub(net_total: 1_000_000, blk_total: 500_000)
    OpenStruct.new(
      cpu_stats: OpenStruct.new(
        online_cpus: 4,
        system_cpu_usage: 2_000_000_000_000,
        cpu_usage: OpenStruct.new(total_usage: 500_000_000_000)
      ),
      precpu_stats: OpenStruct.new(
        system_cpu_usage: 1_000_000_000_000,
        cpu_usage: OpenStruct.new(total_usage: 450_000_000_000)
      ),
      memory_stats: OpenStruct.new(
        usage: 67_108_864,
        limit: 134_217_728,
        max_usage: 100_000_000
      ),
      networks: {
        "eth0" => OpenStruct.new(rx_bytes: net_total, tx_bytes: net_total)
      },
      blkio_stats: OpenStruct.new(
        io_service_bytes_recursive: [
          OpenStruct.new(op: "read", value: blk_total),
          OpenStruct.new(op: "write", value: blk_total)
        ]
      )
    )
  end

  def stub_docker_list(containers_list)
    client = Object.new
    client.define_singleton_method(:containers) do
      Object.new.tap do |c|
        c.define_singleton_method(:list) { |**| containers_list }
      end
    end

    ContainersController.define_method(:docker_client) { client }
    yield
  ensure
    ContainersController.send(:remove_method, :docker_client)
  end

  def stub_docker_inspect(container_id, container)
    client = Object.new
    client.define_singleton_method(:containers) do
      Object.new.tap do |c|
        c.define_singleton_method(:inspect_) { |id| container }
      end
    end

    ContainersController.define_method(:docker_client) { client }
    yield
  ensure
    ContainersController.send(:remove_method, :docker_client)
  end

  def stub_docker_stats(container_id, stats_obj, &block)
    stub_docker_stats_sequence(container_id, [ stats_obj ], &block)
  end

  def stub_docker_stats_sequence(container_id, stats_objects, &block)
    call_count = 0
    client = Object.new
    client.define_singleton_method(:containers) do
      Object.new.tap do |c|
        c.define_singleton_method(:stats) do |id, **|
          stats_obj = stats_objects[[ call_count, stats_objects.length - 1 ].min]
          call_count += 1
          stats_obj
        end
      end
    end

    ContainersController.define_method(:docker_client) { client }
    block.call
  ensure
    ContainersController.send(:remove_method, :docker_client)
  end

  def build_container_stub(id, status: :running, running: true, exit_code: 0, finished_at: nil)
    state = OpenStruct.new(
      status: status,
      running: running,
      paused: false,
      restarting: false,
      dead: false,
      exit_code: exit_code,
      error: "",
      started_at: "2026-07-23T09:00:00Z",
      finished_at: finished_at,
      oom_killed: false
    )

    config = OpenStruct.new(
      cmd: ["nginx", "-g", "daemon off;"],
      entrypoint: [],
      env: ["NGINX_HOST=localhost", "NGINX_PORT=80"],
      user: nil,
      working_dir: "/",
      exposed_ports: { "80/tcp" => {}, "443/tcp" => {} },
      labels: { "com.example.version" => "1.0" }
    )

    host_config = OpenStruct.new(
      network_mode: "bridge",
      privileged: false,
      port_bindings: { "80/tcp" => [OpenStruct.new(host_ip: "0.0.0.0", host_port: "8080")] },
      binds: ["/host/data:/data:rw"],
      memory: 134_217_728,
      memory_swap: 268_435_456,
      cpu_shares: 512,
      cpuset_cpus: "0-1",
      restart_policy: OpenStruct.new(name: "always")
    )

    mounts = [
      OpenStruct.new(type: "bind", source: "/host/data", destination: "/data", driver: nil, mode: "rw", name: nil),
      OpenStruct.new(type: "volume", source: "myvolume", destination: "/var/lib/data", driver: "local", mode: "z", name: "myvolume")
    ]

    network_settings = OpenStruct.new(
      networks: {
        "bridge" => OpenStruct.new(
          ip_address: "172.17.0.2",
          ip_prefix_len: 16,
          gateway: "172.17.0.1",
          mac_address: "02:42:ac:11:00:02",
          network_id: "net123"
        )
      },
      ports: { "80/tcp" => [OpenStruct.new(host_ip: "0.0.0.0", host_port: "8080")] }
    )

    OpenStruct.new(
      decorator_name: "container",
      id: id,
      name: "/web-app",
      image: "nginx:1.25",
      platform: "linux",
      created: Time.parse("2026-07-23T08:00:00Z"),
      restart_count: 2,
      size_rw: 4_194_304,
      size_root_fs: 201_326_592,
      driver: "overlay2",
      hostname_path: "/var/lib/docker/containers/#{id}/hostname",
      hosts_path: "/var/lib/docker/containers/#{id}/hosts",
      resolv_conf_path: "/var/lib/docker/containers/#{id}/resolv.conf",
      log_path: "/var/lib/docker/containers/#{id}/#{id}-json.log",
      state: state,
      config: config,
      host_config: host_config,
      mounts: mounts,
      network_settings: network_settings
    )
  end

end
