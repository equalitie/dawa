require "docker_engine_ruby"

class ContainersController < BaseAdminController
  include DockerClientConcern

  before_action :fetch_container, only: [ :show, :destroy ]

  def index
    @containers = docker_client.containers.list(all: true)
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

  def update
    if params[:command]
      ContainerJob.perform_later(params[:id], params[:command])
    end
    head :ok
  end

  def destroy
    docker_client.containers.delete(@container.id)
    redirect_to containers_path, notice: t("containers.destroyed")
  rescue DockerEngineRuby::Errors::APIConnectionError => e
    redirect_to containers_path, alert: "Could not connect to Docker: #{e.cause}"
  rescue DockerEngineRuby::Errors::APIStatusError => e
    redirect_to containers_path, alert: "Docker error: #{e.cause}"
  end

  private

  def fetch_container
    @container = docker_client.containers.inspect_(params[:id])
  end
end
