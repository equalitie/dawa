#
# The running state of an installed app, as a badge. Pending is optional
# and overrides app.status.
#
#   = v.app_status_badge(app, pending: "starting")
#
class AppStatusBadgeComponent < StateBadgeComponent
  self.map = {
    "running" => [ "success", "apps.status.running" ],
    "stopped" => [ "secondary", "apps.status.stopped" ],
    "start"   => [ "info", "apps.status.starting" ],
    "stop"    => [ "info", "apps.status.stopping" ],
    "restart" => [ "info", "apps.status.restarting" ],
    nil => [ "dark", "apps.status.unknown" ]
  }

  def initialize(app, pending: nil, **kwargs)
    @pending = pending
    @app = app
    super(app, **kwargs)
  end

  def field_value(obj)
    @pending || @app&.status
  end
end
