require "docker_engine_ruby"

class ContainersController < ApplicationController
  before_action :fetch_container, only: :show

  def index
    @containers = docker_client.containers.list(all: false)
  rescue DockerEngineRuby::Errors::APIConnectionError => e
    @error = "Could not connect to Docker: #{e.cause}"
  rescue DockerEngineRuby::Errors::RateLimitError => e
    @error = "Too many requests; we should back off a bit."
  rescue DockerEngineRuby::Errors::APIStatusError => e
    @error = "Docker error: #{e.cause}"
  ensure
    @containers ||= []
  end

  def show
  end

  def restart
    docker_client.containers.restart(params[:id])
    redirect_to container_path(params[:id]), notice: t(".restarting")
  rescue DockerEngineRuby::Errors::APIConnectionError => e
    redirect_to containers_path, alert: "Could not connect to Docker: #{e.cause}"
  rescue DockerEngineRuby::Errors::APIStatusError => e
    redirect_to container_path(params[:id]), alert: "Failed to restart container: #{e.message}"
  end

  private

  def fetch_container
    @container = docker_client.containers.inspect_(params[:id])
  end

  def docker_client
    @docker_client ||= begin
      client_options = {
        max_retries: 2,
        timeout: 60,
        base_url: Conf.docker_url
      }
      DockerEngineRuby::Client.new(**client_options)
    end
  end

end
