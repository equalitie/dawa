# VictoriaMetrics

The compose file exposes victoria metrics at http://localhost:8428. There is no access control.

To load the UI, open http://localhost:8428/vmui. There is not much there. VictoriaMetrics is just the metrics, dashboards are typically handled by Graphana or in our case Dawa.

The VictoriaMetrics endpoint lets you perform queries and get back data. The /vmui is just useful for writing queries but would be disabled in production. Also, eventually, victoria metrics endpoint should only be available to Dawa and no other container, although the victoria metrics container still needs to poll all the other containers.

## Example API Usage

Get a list of all the instance names:

```
curl -s --get 'http://localhost:8428/api/v1/label/instance/values'
```

Get a list of all the metrics that are available for a specific instance:

```
curl -s --get 'http://localhost:8428/api/v1/label/__name__/values' \
  --data-urlencode 'match[]={__name__=~".+",instance="host.docker.internal:9100"}'
```

List all instances with a specific metric:

```
curl -s --get 'http://localhost:8428/api/v1/label/instance/values' \
  --data-urlencode 'match[]=node_cpu_seconds_total'
```

## Queries

To run a query, load the UI at http://localhost:8428/vmui or run `curl -s --get 'http://localhost:8428/api/v1/query' --data-urlencode 'query=QUERY_STRING'`

The status of each instance (quick way to query all instance names):

```
up
```

CPU usage by instance:

```
100 * (1 - avg(rate(node_cpu_seconds_total{job="node", mode="idle"}[5m])) by (instance))
```

Memory usage by instance in MB:

```
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / 1024 / 1024
```

Memory usage for a single instance:

```
(node_memory_MemTotal_bytes{instance="host.docker.internal:9100"} - node_memory_MemAvailable_bytes{instance="host.docker.internal:9100"}) / 1024 / 1024
```

Disk usage (GB):

capacity, used, free:

```
node_filesystem_size_bytes{mountpoint="/"} / 1024 / 1024 / 1024

(node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_avail_bytes{mountpoint="/"}) / 1024 / 1024 / 1024

node_filesystem_avail_bytes{mountpoint="/"} / 1024 / 1024 / 1024
```

Network (Mbps):

```
rate(node_network_receive_bytes_total{device!~"lo|docker.*|veth.*|br-.*|tailscale.*|virbr.*", instance="host.docker.internal:9100"}[5m]) * 8 / 1000000

rate(node_network_transmit_bytes_total{device!~"lo|docker.*|veth.*|br-.*|tailscale.*|virbr.*", instance="host.docker.internal:9100"}[5m]) * 8 / 1000000
```

network errors:

* node_network_receive_errs_total
* node_network_transmit_errs_total
* node_network_receive_drop_total
* node_network_transmit_drop_total

# Real time metrics

Typically, we want long term historical time series data. In some cases, however, we want direct "live" data on a 1-2 second interval. 

VictoriaMetrics could support this by converting a common source into two metrics, one that is downsampled to 30s and one that includes the raw 1s sample. However, vmagent does not support different retention periods for different metrics (a single global `-retentionPeriod=TIME` flag). To support real time data this would mean we either have a massive database with a lot of samples or we run two `vmagent` processes, one with a normal retention period and one with a short retention period.

Two relevant container images:

* `victoriametrics/victor-metrics`: all in one image with db and vmagent and ui.
* `victoriametrics/vmagent`: just the agent.

`vmagent` handles metrics collection and forwarding to the database.
