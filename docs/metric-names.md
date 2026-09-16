# vector host metrics

metrics exported by the `host_metrics` source in vector.

These are the actual names of the metrics:

```
curl -s 'http://localhost:8428/api/v1/label/__name__/values'   --data-urlencode 'match[]={__name__=~"host_.*"}' | jq
```

```
host_boot_time
host_cpu_seconds_total
host_disk_read_bytes_total
host_disk_reads_completed_total
host_disk_writes_completed_total
host_disk_written_bytes_total
host_filesystem_free_bytes
host_filesystem_inodes_free
host_filesystem_inodes_total
host_filesystem_inodes_used
host_filesystem_inodes_used_ratio
host_filesystem_total_bytes
host_filesystem_used_bytes
host_filesystem_used_ratio
host_load1
host_load15
host_load5
host_logical_cpus
host_memory_active_bytes
host_memory_available_bytes
host_memory_buffers_bytes
host_memory_cached_bytes
host_memory_free_bytes
host_memory_shared_bytes
host_memory_swap_free_bytes
host_memory_swap_total_bytes
host_memory_swap_used_bytes
host_memory_swapped_in_bytes_total
host_memory_swapped_out_bytes_total
host_memory_total_bytes
host_memory_used_bytes
host_network_receive_bytes_total
host_network_receive_errs_total
host_network_receive_packets_total
host_network_transmit_bytes_total
host_network_transmit_errs_total
host_network_transmit_packets_drop_total
host_network_transmit_packets_total
host_physical_cpus
host_uptime
```

These are the names in the documentation. In practice, some of these appear missing and most have host_ prefixed.

**Boot Time**
- `boot_time` (gauge): The UNIX timestamp of the last boot.
  - Labels: `collector`, `host`

**Disk**
- `disk_read_bytes_total` (counter): Accumulated number of bytes read.
- `disk_reads_completed_total` (counter): Accumulated number of read operations completed.
- `disk_writes_completed_total` (counter): Accumulated number of write operations completed.
- `disk_written_bytes_total` (counter): Accumulated number of bytes written.
  - Labels: `collector`, `device`, `host`

**Filesystem**
- `filesystem_free_bytes` (gauge): Number of bytes free on the filesystem.
- `filesystem_total_bytes` (gauge): Total number of bytes in the filesystem.
- `filesystem_used_bytes` (gauge): Number of bytes used on the filesystem.
- `filesystem_used_ratio` (gauge): Ratio between used and total bytes.
  - Labels: `collector`, `device`, `filesystem`, `host`

**Host CPU**
- `host_cpu_seconds_total` (counter): CPU seconds accumulated in different operating modes.
  - Labels: `collector`, `cpu`, `host`, `mode`
- `host_logical_cpus` (gauge): The number of logical CPUs.
- `host_physical_cpus` (gauge): The number of physical CPUs.

**Load**
- `load1` (gauge): System load averaged over the last 1 minute.
- `load5` (gauge): System load averaged over the last 5 minutes.
- `load15` (gauge): System load averaged over the last 15 minutes.
  - Labels: `collector`, `host`

**Memory**
- `memory_active_bytes` (gauge): Number of bytes of active main memory.
- `memory_available_bytes` (gauge): Number of bytes of main memory available.
- `memory_buffers_bytes` (gauge): Number of bytes of main memory used by buffers.
- `memory_cached_bytes` (gauge): Number of bytes of main memory used by cached blocks.
- `memory_free_bytes` (gauge): Number of bytes of main memory not used.
- `memory_inactive_bytes` (gauge): Number of bytes of main memory that is not active.
- `memory_shared_bytes` (gauge): Number of bytes of main memory shared between processes.
- `memory_swap_free_bytes` (gauge): Number of free bytes of swap space.
- `memory_swap_total_bytes` (gauge): Total number of bytes of swap space.
- `memory_swap_used_bytes` (gauge): Number of used bytes of swap space.
- `memory_swapped_in_bytes_total` (counter): Number of bytes swapped into main memory.
- `memory_swapped_out_bytes_total` (counter): Number of bytes swapped out from main memory.
- `memory_total_bytes` (gauge): Total number of bytes of main memory.
- `memory_used_bytes` (gauge): Number of bytes of main memory used by programs or caches.
- `memory_wired_bytes` (gauge): Number of wired bytes of main memory.
  - Labels: `collector`, `host`

**Network**
- `network_receive_bytes_total` (counter): Number of bytes received on this interface.
- `network_receive_errs_total` (counter): Number of receive errors on this interface.
- `network_receive_packets_total` (counter): Number of packets received on this interface.
- `network_transmit_bytes_total` (counter): Number of bytes transmitted on this interface.
- `network_transmit_errs_total` (counter): Number of transmit errors on this interface.
- `network_transmit_packets_drop_total` (counter): Number of packets dropped during transmits.
- `network_transmit_packets_total` (counter): Number of packets transmitted on this interface.
  - Labels: `collector`, `device`, `host`

**Process**
- `process_cpu_usage` (gauge): Process CPU usage.
- `process_memory_usage` (gauge): Process memory usage.
- `process_memory_virtual_usage` (gauge): Process virtual memory usage.
- `process_runtime` (counter): Process uptime.
  - Labels: `collector`, `host`

**TCP**
- `tcp_connections_total` (gauge): Number of TCP connections.
  - Labels: `collector`, `host`, `state`
- `tcp_rx_queued_bytes_total` (gauge): Number of bytes in the receive queue across all connections.
- `tcp_tx_queued_bytes_total` (gauge): Number of bytes in the send queue across all connections.
  - Labels: `collector`, `host`

**Temperature**
- `temperature_celsius` (gauge): Current temperature reported by a hardware component, in degrees Celsius.
- `temperature_critical_celsius` (gauge): Temperature at which a hardware component is considered critical, in degrees Celsius.
- `temperature_max_celsius` (gauge): Highest temperature recorded for a hardware component, in degrees Celsius.
  - Labels: `collector`, `component`, `host`

**Uptime**
- `uptime` (gauge): Number of seconds since the last boot.
  - Labels: `collector`, `host`

# logporter metrics

```
curl -s 'http://localhost:8428/api/v1/label/__name__/values'   --data-urlencode 'match[]={__name__=~"docker_.*"}' | jq
```

```
docker_bind_mounts
docker_container_healthy
docker_container_running_count
docker_container_status
docker_container_stopped_count
docker_cpu_total_number
docker_cpu_usage_kernel
docker_cpu_usage_total
docker_cpu_usage_user
docker_exit_code
docker_image_count
docker_image_size
docker_image_update
docker_io_read_bytes
docker_io_write_bytes
docker_memory_current_limit
docker_memory_inspect_limit
docker_memory_total
docker_memory_usage
docker_network_received_bytes
docker_network_received_packages
docker_network_transmit_bytes
docker_network_transmit_packages
docker_oom_killed
docker_process_pids_count
docker_size_root_fs
docker_size_rw
docker_started_time
docker_volume_mounts
```

| Name                                | Data type     | Help description
| -                                   | -             | -
| docker_image_count                  | `gauge`       | Number of images
| docker_image_size                   | `gauge`       | The size of the image minus the layer shared by other images
| docker_image_update                 | `gauge`       | Image update status based on digests: update required (1) or latest version (0)
| docker_volume_size                  | `gauge`       | The size of the volumes and the number of containers associated with it in the volumeUsage tag
| docker_container_running_count      | `gauge`       | Number of running containers
| docker_container_stopped_count      | `gauge`       | Number of stopped containers
| docker_container_status             | `gauge`       | Container status: running (1) or stopped (0)
| docker_container_healthy            | `gauge`       | Health check status
| docker_started_time                 | `gauge`       | Container started timestamp
| docker_exit_code                    | `gauge`       | Container exit code
| docker_oom_killed                   | `gauge`       | Memory limit exceeded
| docker_size_rw                      | `gauge`       | Size of the container writable layer in bytes
| docker_size_root_fs                 | `gauge`       | Total size of the container filesystem in bytes (shared image layers and writable layer)
| docker_bind_mounts                  | `gauge`       | Number of volumes mounted on host file system
| docker_volume_mounts                | `gauge`       | Number of local volumes mounted
| docker_cpu_total_number             | `gauge`       | Total available vCPUs
| docker_cpu_usage_total              | `counter`     | Total CPU usage (user and kernel) in seconds
| docker_cpu_usage_user               | `counter`     | User CPU usage in seconds
| docker_cpu_usage_kernel             | `counter`     | Kernel CPU usage in seconds
| docker_memory_total                 | `gauge`       | Total memory size in bytes 
| docker_memory_current_limit         | `gauge`       | Current memory limit size in bytes (if no value is specified, the total amount of available memory is displayed)
| docker_memory_inspect_limit         | `gauge`       | Memory limit size in bytes specified in the launch options (if the value is 0, then no limit is set)
| docker_memory_usage                 | `gauge`       | Usage memory size in bytes 
| docker_network_received_bytes       | `counter`     | Number of bytes received on the network
| docker_network_received_packages    | `counter`     | Number of packages received on the network
| docker_network_transmit_bytes       | `counter`     | Number of bytes transmitted on the network
| docker_network_transmit_packages    | `counter`     | Number of packages transmitted on the network
| docker_io_read_bytes                | `counter`     | Number of bytes read by the block device
| docker_io_write_bytes               | `counter`     | Number of bytes write by the block device
| docker_process_pids_count           | `gauge`       | Number of running processes and threads

# logporter labels

List of available labels for container filtering:

| Label             | Description
| -                 | - 
| `hostname`        | Hostname obtained from the Docker API or custom from the `DOCKER_METRICS_HOSTNAME` variable
| `containerId`     | Unique container identifier
| `containerName`   | Container name from `container_name` in compose file
| `containerState`  | The current status of the container (if the state is not running, then only inspect metrics are available)
| `composeProject`  | Name of the compose project (usually the name of the directory where the compose file is located)
| `composeService`  | Name of the service in the compose project (may differ from `containerName`)
| `composeWorkDir`  | Path to the directory with the compose stack on the host
