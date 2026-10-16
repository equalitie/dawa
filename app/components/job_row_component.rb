#
# One job in the app show page's job list, as a table row.
#
class JobRowComponent < TableBaseComponent
  haml_template <<~HAML
    = v.table_row(id: @job.dom_id) do |row|
      - row.columns_definition = self.columns_definition
      - row.with_cell do
        = row.link_to(started_cell, job_path)
      - row.with_cell do
        = row.link_to(v.job_state_badge(@job), job_path)
      - row.with_cell do
        = row.link_to(type_cell, job_path)
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
    #safe_join([
    #  content_tag(:span, type_label, class: "fw-semibold"),
    #  content_tag(:div, content_tag(:code, @job.id), class: "small text-muted text-nowrap")
    #])
    content_tag(:span, type_label, class: "fw-semibold")
  end

  def started_cell
    if @job.started_time
      helpers.time_ago(@job.started_time)
    else
      content_tag(:em, t("jobs.time_unknown"), class: "text-muted", data: {placeholder: "true"})
    end
  end

  def outcome_cell
    label = @job.terminal? ? outcome_label : t("jobs.in_progress")
    label
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
