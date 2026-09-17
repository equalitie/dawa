#
# The installed apps: what dcommsctl is actually running on this host.
#
# This is the counterpart of CatalogController, which lists what CAN be installed. An
# "app" here is a deployment with its own data; a catalog entry is the thing it was
# created from (see the vocabulary note in dcomms.rb).
#
# Read-only for now. The lifecycle actions (start/stop/backup/restore) exist on the
# adapter but are not wired to the UI yet.
#
class AppsController < BaseAdminController
  def index
    @apps = apps
  rescue DcommsClient::Error => e
    @apps = []
    @error = e.message
  end

  private

  def apps
    adapter.apps_installed_list
  end

  # Never talk to DcommsClient directly; the adapter owns the real/mock decision.
  def adapter
    @adapter ||= DcommsAdapter.new
  end
end
