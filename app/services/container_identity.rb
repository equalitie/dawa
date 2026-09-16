require "socket"

#
# Determines whether a given container is the very container this Dawa instance runs in.
#
# If Dawa were allowed to start/stop/restart/delete its own container \, the background worker
# that runs the container job would be torn down before it can record the job as finished.
#
# The queue then re-claims the unfinished execution on the next boot and restarts Dawa again,
# forever. This guard exists so Dawa can't act on itself.
#
# On Docker a container's hostname defaults to its own (short) container id, so comparing the
# target container id's prefix against our hostname reliably identifies "the container we run in"
# without needing an extra Docker API call.
#
class ContainerIdentity
  def self.own_container?(container_id, self_id: ContainerIdentity.id)
    own = self_id.to_s.downcase
    target = container_id.to_s.downcase
    return false if own.blank? || target.blank?

    target.start_with?(own)
  end

  def self.id
    ENV.fetch("HOSTNAME") { Socket.gethostname }
  end
end
