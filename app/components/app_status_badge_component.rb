#
# The running state of an installed app, as a badge.
#
#   = v.app_status_badge(app)
#
# `inst/list` reports "running" or "stopped", or nothing at all when the daemon could not
# ask docker compose (unreachable, no compose file, ...). A missing status means UNKNOWN,
# not "stopped" -- those are different claims and only one of them is true -- so it gets
# its own label rather than falling through to the stopped one.
#
# The nil key is the missing case: `AppInstance` normalizes a blank status to nil (via
# `presence`), and StateBadgeComponent looks the field up without stringifying it away.
#
# Unrecognized values render no badge at all, which is StateBadgeComponent's behaviour: a
# state we do not know is better left unlabelled than shown with a colour that means
# something else.
#
class AppStatusBadgeComponent < StateBadgeComponent
  self.field = :status
  self.map = {
    "running" => [ "success", "apps.status.running" ],
    "stopped" => [ "secondary", "apps.status.stopped" ],
    nil => [ "dark", "apps.status.unknown" ]
  }
end
