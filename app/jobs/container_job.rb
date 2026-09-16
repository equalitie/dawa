class ContainerJob < ApplicationJob
  queue_as :default

  def perform(container_id, action)
    @container_id = container_id
    container = docker_client.containers.inspect_(@container_id)

    if action == "start"
      if [:exited, :created].include? container.state.status
        broadcast_refresh(mock_container(status: :starting))
        docker_client.containers.start(@container_id)
      elsif :paused == container.state.status
        broadcast_refresh(mock_container(status: :starting))
        docker_client.containers.unpause(@container_id)
      else
        broadcast_error("container is not in a state that can be started")
      end
    elsif action == "stop"
      broadcast_refresh(mock_container(status: :stopping))
      docker_client.containers.stop(container_id)
    elsif action == "restart"
      broadcast_refresh(mock_container(status: :restarting))
      docker_client.containers.restart(container_id)
    end

    container = docker_client.containers.inspect_(container_id)
    broadcast_refresh(container)
  rescue DockerEngineRuby::Errors::APIConnectionError => e
    broadcast_error("Could not connect to Docker: #{e.cause}")
  rescue DockerEngineRuby::Errors::APIStatusError => e
    broadcast_error("Failed to restart container: #{e.message}")
  end

  private

  def mock_container(**state_options)
    OpenStruct.new(
      id: @container_id,
      name: "/",
      decorator_name: "container",
      state: OpenStruct.new(**state_options)
    )
  end

  def container_box_html(container)
    renderer.render(partial: "containers/show/container_box", locals: { container: container })
  end

  def status_badge_html(container)
    renderer.render(inline: "<%= d(container).state_badge %>", locals: { container: container })
  end

  def broadcast_refresh(container)
    broadcast_status_badge(status_badge_html(container))
    Turbo::StreamsChannel.broadcast_replace_to(@container_id, target: "container-box-#{@container_id}", content: container_box_html(container))
  end

  def broadcast_error(message)
    broadcast_message_to(@container_id, message)
    broadcast_message_to("containers", message)
  end

  def broadcast_status_badge(html)
    turbo_stream_replace_to(@container_id, target: "container-status-#{@container_id}", content: html)
    turbo_stream_replace_to("containers", target: "container-status-#{@container_id}", content: html)
  end

  def renderer
    @renderer ||= ApplicationController.renderer.new(
      https: false,
      http_host: "localhost"
    )
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
