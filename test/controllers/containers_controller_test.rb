require_relative "../test_helper"
require "docker_engine_ruby"

class ContainersControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(username: "container-test-#{SecureRandom.hex(4)}", is_admin: true)
  end

  def test_index_renders_table_when_docker_available
    container = OpenStruct.new(id: "id-123", names: ["/web-app"], image: "nginx:latest", status: "Up 2 hours", created: 1.hour.ago.to_i)

    stub_docker_list([container]) do
      sign_in
      get containers_path
    end

    assert_response :success
    assert_select "td", text: "web-app"
  end

  def test_index_handles_connection_error
    ContainersController.define_method(:docker_client) { raise DockerEngineRuby::Errors::APIConnectionError.new(url: URI.parse("http://localhost")) }

    sign_in
    get containers_path

    assert_response :success
    assert_select ".alert-danger"
  ensure
    ContainersController.send(:remove_method, :docker_client)
  end

  def test_index_empty_list
    stub_docker_list([]) do
      sign_in
      get containers_path
    end

    assert_response :success
  end

  def test_restart_redirects_to_container
    container_id = "restart-test-1"

    client = Object.new
    client.define_singleton_method(:containers) do
      Object.new.tap do |c|
        c.define_singleton_method(:restart) { |id| nil }
      end
    end

    ContainersController.define_method(:docker_client) { client }

    sign_in
    post restart_container_path(container_id)

    assert_redirected_to container_path(container_id)
  ensure
    ContainersController.send(:remove_method, :docker_client)
  end

  def test_restart_handles_connection_error
    ContainersController.define_method(:docker_client) { raise DockerEngineRuby::Errors::APIConnectionError.new(url: URI.parse("http://localhost")) }

    sign_in
    post restart_container_path("any-id")

    assert_redirected_to containers_path
  ensure
    ContainersController.send(:remove_method, :docker_client)
  end

  def test_show_renders_container_details
    container_id = "abc123def456"
    container = build_container_stub(container_id)

    stub_docker_inspect(container_id, container) do
      sign_in
      get container_path(container_id)
    end

    assert_response :success
    assert_select "code", text: container_id
    assert_select "td", text: "nginx:1.25"
    assert_select ".badge.bg-success", text: "Running"
  end

  def test_show_shows_exited_status
    container_id = "dead0000beef"
    container = build_container_stub(container_id, running: false, exit_code: 0, finished_at: "2026-07-23T10:00:00Z")

    stub_docker_inspect(container_id, container) do
      sign_in
      get container_path(container_id)
    end

    assert_response :success
    assert_select ".badge.bg-secondary", text: "Exited"
  end

  def test_show_shows_error_status
    container_id = "err00000001"
    container = build_container_stub(container_id, running: false, exit_code: 137, finished_at: "2026-07-23T10:00:00Z")

    stub_docker_inspect(container_id, container) do
      sign_in
      get container_path(container_id)
    end

    assert_response :success
    assert_select ".badge.bg-danger", text: "Exited (137)"
  end

  private

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

  def build_container_stub(id, running: true, exit_code: 0, finished_at: nil)
    state = OpenStruct.new(
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

  def sign_in
    post demo_session_path, params: { username: @user.username }
    follow_redirect!
  end
end
