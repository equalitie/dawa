#
# A job's state, as a badge.
#
#   = v.job_state_badge(job)
#
# The daemon's states are pending/running/done/failed (jobs.go's JobState). `pending` and
# `running` are both "in flight"; only `done` means success and only `failed` carries an
# exit code and an error message.
#
# An unrecognized state renders no badge (StateBadgeComponent's behaviour) rather than
# borrowing a colour that would claim something untrue.
#
class JobStateBadgeComponent < StateBadgeComponent
  self.field = :state
  self.map = {
    "pending" => [ "warning", "jobs.state.pending" ],
    "running" => [ "info", "jobs.state.running" ],
    "done" => [ "success", "jobs.state.done" ],
    "failed" => [ "danger", "jobs.state.failed" ]
  }
end
