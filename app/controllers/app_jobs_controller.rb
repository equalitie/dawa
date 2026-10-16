class AppJobsController < BaseAdminController
  include DcommsClientConcern

  def show
    @app = app_get(params[:app_id])
    return head :not_found if @app.nil?

    @job = job_get(params[:id])
    return head :not_found if @job.nil?

    @log = log_get(@job)
  rescue DcommsClient::Error => e
    @error = e.message
    @log = nil
  end

  def index
    @app = app_get(params[:app_id])
    @jobs = sort_jobs(jobs(@app))
  end
end
