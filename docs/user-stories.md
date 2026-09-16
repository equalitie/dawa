# Personas

## Operator

An operator is responsible for the installation, upkeep, and day-to-day care of
the dcomms server. This is the same work a sysadmin would normally do, but instead of doing
it manually on the command line, the operator relies on dComms system to handle the heavy
lifting of implementation.

The operator:

- is competent and takes responsibility for the health of the system, but does **not**
  need deep, low-level technical knowledge to perform routine tasks;
- wants the software to expose safe, guided tools so they can update, back up, monitor,
  upgrade, troubleshoot, and respond to incidents **without SSH-ing into boxes** or
  hand-editing config files;
- is accountable for backup integrity and data safety;
- experiences repeated, predictable, high-risk tasks (updates, restores, incident
  response) where the software can reduce human error and time-to-resolution.
- where a sysadmin would reach for a shell, a command, a cron job, or a manual checklist,
  dComms should offer an equivalent guided, repeatable, auditable tool.

# Conventions

| Label | Meaning |
|-------|---------|
| `P0`  | Must have for release; blocks core value |
| `P1`  | Important; include early |
| `P2`  | Nice to have; schedule when capacity allows |
| `P3`  | Later; exploratory or polish |
| `P?`  | Maybe; could be useful but could be more advanced than we need |

# Installation

The operator must be able to install dComms on a server running a fresh installation of Debian stable.

### Bootstrap command

As an **operator**, I want to **run a console command to install dComms base platform on a Debian server** so that I can start using dComms.
`P0`

### Remote bootstrap

As an **operator**, I want to **install dComms base platform using a remote application** so that I can start using dComms without using the command line.
`P?`

### DNS Setup

As an **operator**, I want to **configure DNS** so that users can access services on my dComms server.
`P0`

### System configuration

As an **operator**, I want to **configure my dComms server through the web UI** so that I can customize it to meet my needs without needing to edit configuration files.
`P0`

# User & Account Administration

The operator must be able to manage who can use the system: create, disable, invite, and understand the state of every user.

### Create a user

As an **operator**, I want to **create a new user account from the web UI**, so that I can grant access to a new user.
`P0`

### Create an admin user

As an **operator**, I want to **create a user with admin privileges**, so that I can delegate system administration to trusted colleagues.
`P0`

### Create a regular (non-admin) user

As an **operator**, I want to **create users without admin privileges**, so that team members get the least-privilege access they need.
`P0`

### Disable a user

As an **operator**, I want to **disable a user account** (without deleting it), so that I can immediately revoke access when someone leaves or misbehaves, while preserving their history.
`P0`

### Re-enable a user

As an **operator**, I want to **re-enable a previously disabled user**, so that I can restore access after resolving an issue without recreating the account.
`P0`

### Invite a new user

As an **operator**, I want to **create a self-service setup link**, so that a new user can enroll and choose their own credentials/passkey without me handling secrets on their behalf.
`P0`

### Cancel or expire an invitation

As an **operator**, I want to **cancel or expire a pending invitation**, so that an invitation that was sent in error or misused no longer works.
`P0`

### List users and their status

As an **operator**, I want to **see a list of all users with their status (active / disabled / invited / last seen)**, so that I can tell at a glance who has access and who is active.
`P0`

### Change a user's role

As an **operator**, I want to **promote or demote a user's admin role**, so that I can adjust privileges as responsibilities change without recreating the account.
`P0`

### Edit a user's profile details

As an **operator**, I want to **edit a user's profile** (such as user, avatar, contact information), so that user records stay current and accurate.
`P0`

### Delete a user

As an **operator**, I want to **permanently delete a user account**, so that I can fully remove someone whose data must not be retained.
`P0`

### Reset a user's authentication

As an **operator**, I want to **reset a user's authentication credentials**, so that a user who lost all their passkeys/recovery options can regain access securely.
`P0`

# Updates

The operator must be able to keep the software current safely, with as little risk and as much automation as possible.

### See when an update is available

As an **operator**, I want to **be notified when a new version of the software is available**, so that I can plan maintenance rather than discover vulnerabilities after the fact.
`P0`

### Update with a single action

As an **operator**, I want to **trigger an update from the web UI**, so that I don't have to run shell commands or remember deployment procedures.
`P1`

### Stage updates behind a notice

As an **operator**, I want the system to **show a "maintenance/update pending" notice to users** before and during an update, so that I can avoid surprising them with downtime.
`P1`

### Schedule an update window

As an **operator**, I want to **schedule an update to run at a chosen time**, so that updates happen during low-traffic periods without requiring me to be at the console at 3 a.m.
`P?`

### Control the update channel

As an **operator**, I want to **choose the update channel (stable / beta)**, so that I can decide how conservative the software's update recommendations are.
`P2`

### Get a pre-update health check

As an **operator**, I want the system to **run a health/dependency check before updating**, so that I know in advance whether the update is likely to succeed or will break something.
`P1`

### See an update changelog

As an **operator**, I want to **see what changed in each version** before applying it, so that I can assess risk and communicate changes to users.
`P1`

### Roll back an update

As an **operator**, I want to **roll back to the previous version**, so that I can quickly recover if an update causes problems.
`P1`

### Be told that a restart is required

As an **operator**, I want the system to **flag that a restart/redeploy is needed** after certain updates, so that I don't run with a half-applied upgrade.
`P1`

# Backups

Backup integrity is the operator's safety net. Stories here make backups automatic, verifiable, and portable off-site.

### Configure automatic backups

As an **operator**, I want to **schedule automatic backups** (which data, how often), so that I never rely on remembering to back up.
`P0`

### Back up on demand

As an **operator**, I want to **run a backup right now from the UI**, so that I can capture a clean snapshot before a risky change.
`P0`

### Verify a backup

As an **operator**, I want the system to **verify that backups are restorable**, so that I trust my backups actually work when I need them.
`P0`

### See the backup history

As an **operator**, I want to **see a list of past backups with status (success / failure / size / age)**, so that I can confirm backups are actually being created.
`P0`

### Be alerted on backup failure

As an **operator**, I want to **be alerted if a scheduled backup fails**, so that a silent failure never goes unnoticed.
`P1`

### Copy backups off-site

As an **operator**, I want to **automatically copy backups to an off-site location**, so that I still have a copy if the primary server or datacenter is lost.
`P0`

### Configure a retention policy

As an **operator**, I want to **set how many backups to keep and for how long**, so that old backups are pruned automatically and don't fill the disk.
`P1`

### Restore from a backup

As an **operator**, I want to **restore data from a chosen backup**, so that I can recover from accidental deletion or corruption.
`P0`

### Explore backup data

As an **operator**, I want to **explore the contents of a particular backup**, so that I can retrieve a single piece of information without needing to restore the entire backup.

### Do a test restore

As an **operator**, I want to **perform a safe, sandboxed test restore**, so that I can validate the restore process without risking live data.
`P2`

### Encrypt backups

As an **operator**, I want **backups to be encrypted on the dComms server**, so that sensitive data is safe even if an off-site copy is stolen. `P1`

### Download a backup

As an **operator**, I want to **download a backup file**, so that I can archive it manually when needed for migrations or debugging.
`P2`

# Metrics

The operator needs visibility into system health both in real time and over time.

### See a dashboard of system health

As an **operator**, I want a **single dashboard showing the health of the host and its services**, so that I can quickly determine if anything is wrong.
`P0`

### See real-time resource usage

As an **operator**, I want to **see live CPU, memory, disk, and network usage**, so that I can spot load issues as they happen.
`P0`

### See historical metrics over time

As an **operator**, I want to **see metrics as time-series graphs (days/weeks)**, so that I can detect trends and plan capacity.
`P1`

### Set alert thresholds

As an **operator**, I want to **set thresholds (e.g. CPU > 90%) that trigger alerts**, so that I am notified before a small problem becomes an outage.
`P1`

### Be alerted on service down

As an **operator**, I want to **get an alert when a service or container goes down**, so that I can respond quickly.
`P0`

### See which container uses the most resources

As an **operator**, I want to **see per-container resource usage ranked**, so that I can identify the noisiest or least-efficient workloads.
`P2`

### Track disk usage and growth

As an **operator**, I want to **see disk usage and a projection of when disk will fill**, so that I can add capacity before an outage.
`P1`

### See application health endpoints

As an **operator**, I want to **visualize the health/status endpoints of each service**, so that I can confirm all dependencies are healthy.
`P2`

### Access raw metric data

As an **operator**, I want to **export or inspect raw metric data**, so that I can do deeper analysis or feed it into external tooling.
`P?`

# Logging

Logs are how the operator diagnoses problems. Logs must be viewable, searchable, and retained.

### Stream a service's logs in real time

As an **operator**, I want to **follow a container's log output live in the UI**, so that I can watch an application as it runs.
`P0`

### Search logs

As an **operator**, I want to **search log output by text or regex**, so that I can find relevant events quickly instead of scrolling.
`P1`

### Filter logs by time and severity

As an **operator**, I want to **filter logs by time range and severity level**, so that I can narrow a noisy stream to what matters.
`P1`

### View historical logs

As an **operator**, I want to **browse logs from the past**, so that I can investigate an incident that happened earlier.
`P1`

### Retain logs for a configurable period

As an **operator**, I want to **configure how long logs are retained**, so that I balance diagnostic depth against storage cost.
`P2`

### Export logs

As an **operator**, I want to **export a log range to a file**, so that I can attach it to support tickets or share it.
`P2`

# Troubleshooting

When something breaks, the operator needs guided, safe, low-risk ways to investigate and fix.

### Get a system health / "checkup" button

As an **operator**, I want a **single "Run checkup" action that reports overall health**, so that I can answer "is everything OK?" in one step.
`P1`

### Open a guided diagnostic

As an **operator**, I want to **run a guided diagnostic that checks common causes**, so that I can narrow down a problem without a support expert.
`P1`

### Check a system checkup summary

As an **operator**, I want to **run a "system checkup" that tests connectivity, disk, memory, and key endpoints**, so that I get a one-page health summary.
`P1`

### Get recommended next steps

As an **operator**, I want the tool to **suggest likely fixes with next steps**, so that I don't have to guess what to do when something is wrong.
`P2`

### Capture a support bundle

As an **operator**, I want to **generate a support bundle (logs, config, versions) with one click**, so that I can share exactly what's needed with support.
`P2`

### Undo a mistake

As an **operator**, I want to **undo the last destructive action**, so that a misclick doesn't cause lasting harm.
`P?`

# Container Management

The operator manages containers as the unit of deployment.

### List all containers

As an **operator**, I want to **see all containers with their status**, so that I know what is deployed and running.
`P0`

### Start a stopped container

As an **operator**, I want to **start a stopped container from the UI**, so that I can bring a service back up without the CLI.
`P1`

### Stop a running container

As an **operator**, I want to **stop a running container**, so that I can shut down a service safely.
`P1`

### Restart a container

As an **operator**, I want to **restart a container**, so that I can recover a misbehaving process.
`P0`

### See per-container resource usage

As an **operator**, I want to **see a container's current and historical CPU, memory, network, and disk I/O**, so that I can understand its resource footprint.
`P0`

### See a container's details

As an **operator**, I want to **see a container's full configuration (image, mounts, ports, environment)**, so that I can verify how it is set up.
`P1`

# Application Management

The operator manages applications as the unit of deployment. An application consists of a set of containers, running in concert, to provide an externally available service (either to the public internet or to a private network).

### List possible applications

As an **operator**, I want to **see all installable applications and their details**, so that I can choose a new application to install.
`P0`

### Install a new application

As an **operator**, I want to **easily install a new application**, so that I can add functionality to my dComms server.

### Configure an application

As an **operator**, I want to **easily configure my installed applications through the dComm admin web UI in a friendly manner**, so that I can customize their behavior without editing configuration files or manually setting environment variables.
`P0`

### List all applications

As an **operator**, I want to **see all applications with their status**, so that I know what is deployed and running.
`P0`

### Start a stopped application

As an **operator**, I want to **start a stopped application**, so that I can bring a service back up without the CLI.
`P1`

### Stop a running application

As an **operator**, I want to **stop a running container**, so that I can shut down a service safely.
`P1`

### Restart an application

As an **operator**, I want to **restart a application**, so that I can recover a misbehaving application.
`P0`

### See per-application resource usage

As an **operator**, I want to **see an application's current and historical CPU, memory, network, and disk I/O**, so that I can understand its resource footprint.
`P0`

### See a application's details

As an **operator**, I want to **see a container's full configuration (containers, mounts, ports, environment)**, so that I can verify how it is set up.
`P1`

# Security

The operator is accountable for keeping the system secure and auditable.

### See who logged in and when

As an **operator**, I want to **see a login/activity audit log**, so that I can detect suspicious access.
`P1`

### Terminate sessions

As an **operator**, I want to **be able to terminate active authentication sessions**, so that I can immediately lock a user or all users out of the system if I suspect there has been unauthorized access.
`P1`

### Require strong authentication

As an **operator**, I want to be able to require **accounts use strong authentication**, so that access is protected beyond a password.
`P1`

### See certificate and key status

As an **operator**, I want to **see when TLS certificates and keys expire**, so that I can renew them before they break connections. (with modern approaches using Let's Encrypt, this has become less of an issue, so maybe it won't come up, but certainly a sanity check as part of a diagnostic would be good).
`P?`

### See other operators' actions

As an **operator**, I want to **see a log of administrative actions**, so that I understand what changed and who changed it.
`P2`

### Review permission changes

As an **operator**, I want to **see a record of permission/admin changes**, so that the system is auditable.
`P2`

### Require VPN

As an **operator**, I want to **require that some services are only accessible over a VPN (or i2p or Tor)**, so that the system can obfuscate traffic, add multiple layers to security, or restrict access to certain locations.

# Network Isolation

The operator should be able to upgrade and install applications even if the national internet where the server is located is cut off from the wider internet.

### Upgrades under network isolation

As an **operator**, I want to **be able to update the system and applications** during network isolation, so that I can stay up-to-date on security patches.
`P?`

### DNS resolution under network isolation

As an **operator**, I want to **establish backup name resolution** during network isolation, so that users can access my dComms server.
`P?`

# Incident Response

The operator must be able to respond to, acknowledge, and recover from incidents promptly. Typically, this would be an essential activity for a sysadmin working with other sysadmins on a complex deployment (e.g. using a system like Nagios, etc). In the case of dComms, perhaps none of these are needed. 

### Be alerted to an incident

As an **operator**, I want to **receive an alert when an incident is detected**, so that I can begin a response even if I'm not looking at the dashboard.
`P?`

### Acknowledge an incident

As an **operator**, I want to **acknowledge an incident**, so that the team knows someone is responding.
`P?`

### See the incident timeline

As an **operator**, I want to **see a timeline of what happened (detection, alerts, changes)**, so that I can understand the sequence of events.
`P?`

### Take a recovery action from the incident

As an **operator**, I want to **trigger a recovery action (restart, rollback, restore) directly from the incident**, so that I can resolve it in one flow.
`P?`

### Mark an incident resolved

As an **operator**, I want to **mark an incident resolved and add a note**, so that we have a record of what happened and how it was fixed.
`P?`

### Assign an incident

As an **operator**, I want to **assign an incident to a specific person**, so that ownership of the response is clear.
`P?`

### View open incidents

As an **operator**, I want to **see all open/active incidents**, so that I can prioritize my work.
`P?`

### Mute or silence a noisy alert

As an **operator**, I want to **silence an alert for a period**, so that a known, ongoing issue doesn't flood me with notifications while it's being fixed.
`P?`
