class ContainerDecorator
  def display_name
    if @container.respond_to?(:names)
      @container.names.first.delete_prefix("/")
    elsif @container.respond_to?(:name)
      @container.name.delete_prefix("/")
    end
  end

  def changed
    if @container.respond_to?(:status)
      @container.status
    elsif @container.respond_to?(:state)
      state = @container.state
      if state.status == :running
        start_time = Time.parse(state.started_at)
        "Up #{ActionController::Base.helpers.distance_of_time_in_words(start_time, Time.now)}"
      else
        start_time = Time.parse(state.finished_at)
        "Exited #{ActionController::Base.helpers.distance_of_time_in_words(start_time, Time.now)}"
      end
    end
  end

  def short_id
    @container.id.slice(0, 12)
  end

  # possible Docker API states from inspect:
  #   running, exited, restarting, paused, removing, dead, created
  # from summary (list): state is a symbol directly
  # fake states broadcast by ContainerJob while waiting for Docker:
  #   starting, stopping
  def state_badge
    state = @container.state
    status = state.respond_to?(:status) ? state.status : state
    if status == :running
      badge("success", "running")
    elsif status == :paused
      badge("warning", "paused")
    elsif status == :restarting
      badge("info", "restarting")
    elsif status == :starting
      badge("info", "starting")
    elsif status == :stopping
      badge("warning", "stopping")
    elsif status == :dead
      badge("dark", "dead")
    elsif status == :created
      badge("info", "created")
    elsif status == :removing
      badge("warning", "removing")
    elsif status == :exited
      exit_code = if state.is_a?(Symbol) && @container.respond_to?(:status)
        # handle DockerEngineRuby::Models::Summary differently
        @container.status.gsub(/.*\((\d+)\).*/, "\\1").to_i
      else
        state.exit_code
      end
      if exit_code == 0
        badge("secondary", "exited_ok")
      else
        badge("danger", "exited_error", {code: exit_code})
      end
    else
      badge("dark", "unknown")
    end
  end

  private

  def badge(color, label, label_arg = nil)
    if label_arg
      @view.tag.span(class: "badge bg-#{color}") {
        @view.t("containers.status.#{label}", **label_arg)
      }
    else
      @view.tag.span(class: "badge bg-#{color}") {
        @view.t("containers.status.#{label}")
      }
    end
  end
end
