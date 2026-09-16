class ContainerJob < ApplicationJob
  queue_as :default

  TARGET_STATUSES = {
    start:   :running,
    stop:    :exited,
    restart: :running
  }.freeze

  POLL_INTERVAL = 1.0  # seconds between status checks
  MAX_POLL_TIME  = 30  # seconds before giving up

  def perform(container_id, action)
    @container_id = container_id

    # Never act on the container we're running in: restarting/stopping it would terminate the
    # worker before it can mark the job as finished, leaving Solid Queue to re-run it forever.
    if ContainerIdentity.own_container?(container_id)
      broadcast_error("Dawa cannot manage the container it is running in")
      return
    end

    container = docker_client.containers.inspect_(@container_id)

    if action == "start"
      if [:exited, :created].include? container.state.status
        broadcast_refresh(mock_container(container, status: :starting))
        docker_client.containers.start(@container_id)
      elsif container.state.status == :paused
        broadcast_refresh(mock_container(container, status: :starting))
        docker_client.containers.unpause(@container_id)
      else
        broadcast_error("container is not in a state that can be started")
        return
      end
    elsif action == "stop"
      broadcast_refresh(mock_container(container, status: :stopping))
      docker_client.containers.stop(container_id)
    elsif action == "restart"
      broadcast_refresh(mock_container(container, status: :restarting))
      docker_client.containers.restart(container_id)
    end

    wait_for_target(action.to_sym)

    container = docker_client.containers.inspect_(container_id)
    broadcast_refresh(container)
  rescue DockerEngineRuby::Errors::APIConnectionError => e
    broadcast_error("Could not connect to Docker: #{e.cause}")
  rescue DockerEngineRuby::Errors::APIStatusError => e
    broadcast_error("Failed to restart container: #{e.message}")
  end

  private

  def wait_for_target(action)
    target = TARGET_STATUSES.fetch(action)
    deadline = Time.now + MAX_POLL_TIME

    loop do
      sleep(POLL_INTERVAL)
      current = docker_client.containers.inspect_(@container_id).state.status
      break if current == target
      raise Timeout::Error, "Container did not reach #{target} within #{MAX_POLL_TIME}s (last status: #{current})" if Time.now > deadline
    end
  end

  def mock_container(container, **state_options)
    OpenStruct.new(
      id: container.id,
      name: container.name,
      image: container.respond_to?(:image) ? container.image : nil,
      created: container.respond_to?(:created) ? container.created : Time.now.to_i,
      decorator_name: "container",
      status: "",
      state: OpenStruct.new(**state_options)
    )
  end

  def broadcast_refresh(container)
    stream_replace_to("containers",
      target: "container-row-#{@container_id}",
      partial: "containers/row",
      locals: {container: container}
    )
    stream_replace_to(@container_id,
      target: "container-box-#{@container_id}",
      partial: "containers/show/container_box",
      locals: {container: container}
    )
  end

  def broadcast_error(message)
    stream_message_to(@container_id, message)
    stream_message_to("containers", message)
  end

  def docker_client
    @docker_client ||= begin
      client_options = {
        max_retries: 2,
        timeout: 10,
        base_url: Conf.docker_url
      }
      DockerEngineRuby::Client.new(**client_options)
    end
  end
end
