#
# One job in the app show page's job lists, as a table row.
#
#   = render "jobs/row", job: job, app: app
#
# The log link is offered ONLY for in-flight jobs. This is not a UI preference: the daemon
# serves a finished job's log from a path it no longer updates (it renames `.partial.log` to
# `.log` but leaves the recorded path alone), so `job/log` fails with "no such file" once a
# job completes. A link that can only ever error is worse than no link, so past jobs show
# their outcome instead and no log affordance. See DcommsAdapter#job_log.
#
class JobRowComponent < ApplicationComponent
  haml_template <<~HAML
    = v.table_row(data: {job_id: @job.id}) do |row|
      - row.columns_definition = component_context.columns_definition
      - # ^^ not very graceful, I would like a better way of doing this
      - row.with_cell do
        %span.fw-semibold= type_label
        %div.small.text-muted.text-nowrap
          %code= @job.id
      - row.with_cell do
        = v.job_state_badge(@job)
      - row.with_cell do
        - if @job.started_time
          = helpers.time_tooltip(@job.started_time, helpers.format_time(@job.started_time, :day))
        - else
          %em.text-muted{data: {placeholder: "true"}}= t("jobs.time_unknown")
      - row.with_cell do
        - if @job.terminal?
          %span.small.text-muted= outcome_label
        - else
          %span.small.text-muted= t("jobs.in_progress")
      - row.with_cell do
        - if @job.terminal?
          = t("jobs.log_expired")
        - else
          = v.link_button(label: t("jobs.view_log"), icon: "terminal",
                          url: helpers.app_job_path(@app.id, @job.id), size: "sm")
  HAML

  def initialize(job, app, **args)
    super(**args)
    @job = job
    @app = app
  end

  private

  # `type` is the daemon's job kind (install, start, backup, ...). It is part of the contract
  # but not required, so a job without one says so rather than rendering an empty cell.
  def type_label
    @job.type.presence || t("jobs.type_unknown")
  end

  # A failure states the error, because that is the reason an admin opens this page. The exit
  # code is included only when it says something the message does not.
  def outcome_label
    return t("jobs.failed") if @job.failed? && @job.error.blank?
    return @job.error if @job.failed?

    duration_label
  end

  def duration_label
    seconds = @job.duration
    return t("jobs.duration_unknown") if seconds.nil?
    return t("jobs.duration_instant") if seconds < 1

    t("jobs.duration", duration: helpers.distance_of_time_in_words(seconds))
  end
end
