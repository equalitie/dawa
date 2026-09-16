require_relative "../test_helper"
require "docker_engine_ruby"

class ContainerJobTest < ActiveJob::TestCase
  def setup
    @container_id = "test-container-123"
  end

  def stub_docker_client(inspect_responses: [], start: nil, stop: nil, restart: nil, unpause: nil)
    inspect_call_count = 0
    inspect_responses = Array(inspect_responses)

    client = Object.new
    client.define_singleton_method(:containers) do
      Object.new.tap do |c|
        c.define_singleton_method(:inspect_) do |id|
          resp = inspect_call_count < inspect_responses.length ? inspect_responses[inspect_call_count] : inspect_responses.last
          inspect_call_count += 1
          resp
        end
        c.define_singleton_method(:start)  { |id| start.call(id) } if start
        c.define_singleton_method(:stop)   { |id| stop.call(id) } if stop
        c.define_singleton_method(:restart) { |id| restart.call(id) } if restart
        c.define_singleton_method(:unpause) { |id| unpause.call(id) } if unpause
      end
    end

    ContainerJob.define_method(:docker_client) { client }
    yield
  ensure
    ContainerJob.send(:remove_method, :docker_client)
  end

  def container_with_status(status)
    OpenStruct.new(
      decorator_name: "container",
      id: @container_id,
      name: "/web-app",
      names: ["/web-app"],
      image: "nginx:1.25",
      status: "Up",
      created: Time.now.to_i,
      state: OpenStruct.new(status: status)
    )
  end

  def test_start_created_container
    started = false
    stub_docker_client(
      inspect_responses: [
        container_with_status(:created),
        container_with_status(:running)
      ],
      start: ->(id) { started = true }
    ) do
      ContainerJob.perform_now(@container_id, "start")
    end

    assert started, "docker start should have been called"
  end

  def test_start_exited_container
    started = false
    stub_docker_client(
      inspect_responses: [
        container_with_status(:exited),
        container_with_status(:running)
      ],
      start: ->(id) { started = true }
    ) do
      ContainerJob.perform_now(@container_id, "start")
    end

    assert started, "docker start should have been called"
  end

  def test_start_paused_container_unpauses
    unpaused = false
    stub_docker_client(
      inspect_responses: [
        container_with_status(:paused),
        container_with_status(:running)
      ],
      unpause: ->(id) { unpaused = true }
    ) do
      ContainerJob.perform_now(@container_id, "start")
    end

    assert unpaused, "docker unpause should have been called"
  end

  def test_start_running_container_errors
    stub_docker_client(
      inspect_responses: [ container_with_status(:running) ]
    ) do
      ContainerJob.perform_now(@container_id, "start")
    end

    assert true # no exception should be raised, just an error broadcast
  end

  def test_stop_container
    stopped = false
    stub_docker_client(
      inspect_responses: [
        container_with_status(:running),
        container_with_status(:running),
        container_with_status(:exited)
      ],
      stop: ->(id) { stopped = true }
    ) do
      ContainerJob.perform_now(@container_id, "stop")
    end

    assert stopped, "docker stop should have been called"
  end

  def test_restart_container
    restarted = false
    stub_docker_client(
      inspect_responses: [
        container_with_status(:running),
        container_with_status(:restarting),
        container_with_status(:running)
      ],
      restart: ->(id) { restarted = true }
    ) do
      ContainerJob.perform_now(@container_id, "restart")
    end

    assert restarted, "docker restart should have been called"
  end

  def test_refuses_to_act_on_own_container
    # Restarting the container this Dawa runs in would kill the worker before the job is marked
    # finished, so it must be a no-op that completes (and lets Solid Queue drop it).
    restarted = false
    original = ENV["HOSTNAME"]
    ENV["HOSTNAME"] = @container_id
    stub_docker_client(restart: ->(id) { restarted = true }) do
      ContainerJob.perform_now(@container_id, "restart")
    end
    refute restarted, "docker restart must not be called for Dawa's own container"
  ensure
    original.nil? ? ENV.delete("HOSTNAME") : (ENV["HOSTNAME"] = original)
  end

  def test_connection_error_is_rescued
    ContainerJob.define_method(:docker_client) { raise DockerEngineRuby::Errors::APIConnectionError.new(url: URI.parse("http://localhost")) }

    ContainerJob.perform_now(@container_id, "start")
    assert true # should not raise
  ensure
    ContainerJob.send(:remove_method, :docker_client)
  end
end
