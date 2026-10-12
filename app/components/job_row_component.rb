#
# One job in the app show page's job lists, as a table row.
#
#   = render "jobs/row", job: job, app: app
#
class JobRowComponent < ApplicationComponent
  haml_template <<~HAML
    -# Every cell carries a stretched link (via the table's link_to), so clicking anywhere on the
    -# row opens the job's log page. The links are per-cell because Bootstrap stretches each one
    -# to its nearest positioned ancestor -- the cells -- and the row marks cells position-relative
    -# when hover is on (the default).
    = v.table_row(data: {job_id: @job.id}) do |row|
      - row.columns_definition = component_context.columns_definition
      - # ^^ not very graceful, I would like a better way of doing this
      - row.with_cell do
        = row.link_to(type_cell, job_path)
      - row.with_cell do
        = row.link_to(v.job_state_badge(@job), job_path)
      - row.with_cell do
        = row.link_to(started_cell, job_path)
      - row.with_cell do
        = row.link_to(outcome_cell, job_path)
  HAML

  def initialize(job, app, **args)
    super(**args)
    @job = job
    @app = app
  end

  private

  def job_path = helpers.app_job_path(@app.id, @job.id)

  # The cell content is built as a string so it can be handed to the table's link_to, which
  # takes `(content, url)` rather than a block.
  def type_cell
    safe_join([
      content_tag(:span, type_label, class: "fw-semibold"),
      content_tag(:div, content_tag(:code, @job.id), class: "small text-muted text-nowrap")
    ])
  end

  def started_cell
    if @job.started_time
      helpers.time_tooltip(@job.started_time, helpers.format_time(@job.started_time, :day))
    else
      content_tag(:em, t("jobs.time_unknown"), class: "text-muted", data: {placeholder: "true"})
    end
  end

  def outcome_cell
    label = @job.terminal? ? outcome_label : t("jobs.in_progress")
    content_tag(:span, label, class: "small text-muted")
  end

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
