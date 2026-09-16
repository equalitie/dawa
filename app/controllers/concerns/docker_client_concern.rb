#
# Builds a memoized DockerEngineRuby client for container controllers.
#
module DockerClientConcern
  extend ActiveSupport::Concern

  private

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
