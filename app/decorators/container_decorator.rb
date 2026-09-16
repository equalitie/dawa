class ContainerDecorator
  def display_name
    @container.name.delete_prefix("/")
  end

  def short_id
    @container.id.slice(0, 12)
  end

  # possible states:
  # ["running", "exited", "restarting", "paused", "removing", "dead", "created"]
  # - "created" container has been created but not started
  # - "running" container is currently running
  # - "paused" container has been paused
  # - "restarting" container is in the process of restarting
  # - "removing" container is being removed
  # - "exited" container has run and completed/stoped
  # - "dead" container is dead (non-recoverable error)
  def state_badge
    state = @container.state
    if state.status == :running
      badge("success", "running")
    elsif state.status == :paused
      badge("warning", "paused")
    elsif state.status == :restarting
      badge("info", "restarting")
    elsif state.status == :dead
      badge("dark", "dead")
    elsif state.status == :created
      badge("info", "created")
    elsif state.status == :removing
      badge("warning", "removing")
    elsif state.status = :exited
      if state.exit_code == 0
        badge("secondary", "exited_ok")
      else
        badge("danger", "exited_error", {code: state.exit_code})
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
