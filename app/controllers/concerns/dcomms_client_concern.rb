module DcommsClientConcern
  extend ActiveSupport::Concern

  JOBS_PAGE_SIZE = 5

  def adapter
    @adapter ||= DcommsAdapter.new
  end

  #
  # APPS
  #

  def apps
    adapter.apps_installed_list
  end

  def app_get(id)
    id = id.to_s
    apps.find { |app| app.id == id }
  end

  #
  # JOBS
  #

  def jobs(app, active_only: false)
    adapter.job_list(instance_id: app.id, active_only: active_only)
  end

  def jobs_short_list(app)
    sort_jobs(jobs(app)).first(JOBS_PAGE_SIZE)
  end

  def job_get(job_id)
    adapter.job_status(id: job_id.to_s)
  rescue DcommsClient::EmptyResult
    nil
  end

  #
  # Order jobs by in-progress then by most recent.
  #
  def sort_jobs(jobs)
    jobs.sort_by { |job|
      [
        job.terminal? ? 1 : 0,
        -1 * (job.started_time || Time.at(0)).to_f
      ]
    }
  end

  #
  # LOGS
  #
  def log_get(job)
    adapter.job_log(id: job.id)
  end

end
