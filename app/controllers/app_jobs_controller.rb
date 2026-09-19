#
# One job's log output.
#
# Nested under an app for the URL's sake, and because the page it belongs to is the app's. The
# RPC call itself takes only the job id -- the daemon resolves the instance (see
# DcommsClient#job_log) -- but the instance is still what scopes the job lookup below, so a
# job id from another app cannot be read through this URL.
#
# The daemon only serves the log of a job that is still RUNNING: it renames a finished job's
# `.partial.log` to `.log` but records the new path on the wrong map entry, so `job/log`
# fails with "no such file" once a job completes. That is a daemon bug Dawa cannot work
# around, which is why the show page only links here for in-flight jobs. The check below
# restates that rule at the boundary, so a hand-typed URL for a finished job gets an honest
# message instead of a raw backend error.
#
class AppJobsController < BaseAdminController
  def show
    @app = find_app(params[:app_id])
    return head :not_found if @app.nil?

    @job = find_job(params[:id])
    return head :not_found if @job.nil?

    @log = fetch_log
  rescue DcommsClient::Error => e
    @error = e.message
    @log = nil
  end

  private

  def find_app(id)
    adapter.apps_installed_list.find { |app| app.id == id.to_s }
  end

  # The job must belong to THIS instance and to the instance's own job list, so a job id from
  # another app cannot be read through this URL. The RPC call no longer needs the instance,
  # but this scoping is the reason the route is nested.
  def find_job(id)
    adapter.job_list(instance_id: @app.id).find { |job| job.id == id.to_s }
  end

  def fetch_log
    return nil unless @job.running?

    adapter.job_log(id: @job.id)
  end

  # Never talk to DcommsClient directly; the adapter owns the real/mock decision.
  def adapter
    @adapter ||= DcommsAdapter.new
  end
end
