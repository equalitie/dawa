#
# One installed app, and the jobs dcommsctl has run for it.
#
# An "app" here is a deployment with its own data (see the vocabulary note in dcomms.rb); the
# index lists them all and this shows one.
#
# The daemon has no `inst/get`, so the instance is found by id within `inst/list`. That is
# one extra call compared to a dedicated endpoint, but it keeps Dawa honest about what the
# backend actually offers and it is what the index already pays for.
#
# Jobs come from `job/list`, which filters by `instance_id` server-side. The same call is
# made twice -- once for in-flight work, once for everything -- because `active_only` is a
# daemon-side filter and the two lists mean different things on the page.
#
class AppsController < BaseAdminController
  def index
    @apps = apps
  rescue DcommsClient::Error => e
    @apps = []
    @error = e.message
  end

  def show
    @app = find_app(params[:id])
    # A missing instance is a 404, not an empty page: the id came from a link, so an absent
    # one means the app was uninstalled or the URL is wrong. Reporting "no jobs" would be a
    # different (and false) claim.
    return head :not_found if @app.nil?

    all_jobs = jobs(active_only: false)
    @active_jobs, @past_jobs = partition_jobs(all_jobs)
  rescue DcommsClient::Error => e
    @error = e.message
    @active_jobs = []
    @past_jobs = []
  end

  private

  # Split the jobs for one instance into in-flight and finished.
  #
  # Partitioned here rather than by a second `active_only: true` call: two calls could
  # disagree (a job can finish between them, appearing in the "past" list only), and
  # `JobStatus` has no value equality, so subtracting one list from the other would compare
  # by identity and silently remove nothing. One call is both cheaper and consistent.
  def partition_jobs(jobs)
    jobs.partition { |job| !job.terminal? }
  end

  def apps
    adapter.apps_installed_list
  end

  def find_app(id)
    apps.find { |app| app.id == id.to_s }
  end

  def jobs(active_only:)
    adapter.job_list(instance_id: params[:id], active_only: active_only)
  end

  # Never talk to DcommsClient directly; the adapter owns the real/mock decision.
  def adapter
    @adapter ||= DcommsAdapter.new
  end
end
