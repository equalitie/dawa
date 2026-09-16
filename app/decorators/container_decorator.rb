class ContainerDecorator
  def display_name
    @container.name.delete_prefix("/")
  end

  def short_id
    @container.id.slice(0, 12)
  end

  def state_badge
    state = @container.state
    if state.running
      badge("success", "running")
    elsif state.paused
      badge("warning", "paused")
    elsif state.restarting
      badge("info", "restarting")
    elsif state.dead
      badge("dark", "dead")
    elsif state.exit_code
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
