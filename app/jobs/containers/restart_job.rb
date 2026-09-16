class Containers::RestartJob < ApplicationJob
  queue_as :default

  def perform(container_id)
    @container_id = container_id

    broadcast_restarting

    docker_client.containers.restart(container_id)

    container = docker_client.containers.inspect_(container_id)
    broadcast_refresh(container)
  rescue DockerEngineRuby::Errors::APIConnectionError => e
    broadcast_error("Could not connect to Docker: #{e.cause}")
  rescue DockerEngineRuby::Errors::APIStatusError => e
    broadcast_error("Failed to restart container: #{e.message}")
  end

  private

  def restarting_container
    @restarting_container ||= OpenStruct.new(
      id: @container_id,
      name: "/",
      decorator_name: "container",
      state: OpenStruct.new(
        running: false, paused: false, restarting: true, dead: false, exit_code: nil
      )
    )
  end

  def container_box_html(container)
    renderer.render(partial: "containers/show/container_box", locals: { container: container })
  end

  def status_badge_html(container)
    renderer.render(inline: "<%= d(container).state_badge %>", locals: { container: container })
  end

  def broadcast_restarting
    broadcast_status_badge(status_badge_html(restarting_container))
    Turbo::StreamsChannel.broadcast_replace_to(@container_id, target: "container-box-#{@container_id}", content: container_box_html(restarting_container))
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
