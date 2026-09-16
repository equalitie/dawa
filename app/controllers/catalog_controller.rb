#
# Browse the catalog of installable entries.
#
class CatalogController < BaseAdminController
  def index
    @entries = entries
  rescue DcommsClient::Error => e
    @entries = []
    @error = e.message
  end

  #
  # One catalog entry: what installing it would give you.
  #
  # Read-only like the index. Installing creates an app (a deployment with its own data),
  # which is a different resource and is not wired up yet.
  #
  def show
    @entry = adapter.catalog_entry(id: params[:id])
  rescue DcommsClient::Error => e
    # An unreachable backend is an error state, not a missing record, but both leave the
    # page with nothing to show. `show` renders its own banner rather than falling back to
    # the index, whose error banner makes a different claim ("the catalog is unreachable"
    # reads as "you cannot see any of it").
    @entry = nil
    @error = e.message
  end

  private

  def entries
    adapter.catalog_list
  end

  # Never talk to DcommsClient directly; the adapter owns the real/mock decision.
  def adapter
    @adapter ||= DcommsAdapter.new
  end
end
