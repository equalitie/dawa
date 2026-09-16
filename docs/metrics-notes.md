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

The status of each provider:

```
up
```

Get a list of all the variables exported by a particular job defined in promscrape.yml:

switch to table view, then enter:

```
{job="docker_exporter"}
```

Or, on the command line:

```
curl -s --get 'http://localhost:8428/api/v1/query' --data-urlencode 'query={job="docker_exporter"}' | jq
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

# Labels

some container exporters put labels in a single metric row and then you have to join to filter other metrics rows based on that label:

```
docker_container_cpu_usage_percentage
  * on (id) group_left(container_label_dcomms_app)
  docker_container_labels{container_label_dcomms_app="myapp"}
```

logporter, however, adds the custom label directly to each metric row. this takes up a lot more storage, so we want to make sure not to have too many custom labels. but it also make querying easier:

```
docker_io_write_bytes{dcomms_app="myapp"} 
```

# Real time metrics

Typically, we want long term historical time series data. In some cases, however, we want direct "live" data on a 1-2 second interval. 

VictoriaMetrics could support this by converting a common source into two metrics, one that is downsampled to 30s and one that includes the raw 1s sample. However, vmagent does not support different retention periods for different metrics (a single global `-retentionPeriod=TIME` flag). To support real time data this would mean we either have a massive database with a lot of samples or we run two `vmagent` processes, one with a normal retention period and one with a short retention period.

Two relevant container images:

* `victoriametrics/victor-metrics`: all in one image with db and vmagent and ui.
* `victoriametrics/vmagent`: just the agent.

`vmagent` handles metrics collection and forwarding to the database.

# Host metrics

currently not used in favor of vector.

```yml
  # node-exporter is used to gather metrics on the host.
  # it needs the host's filesystem mounted to /host,
  # and it needs access to the host's network.
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    labels:
      - "dc.int=true"
    restart: unless-stopped
    expose:
      - 9100
    command:
      - '--web.listen-address=:9100'
      - '--path.rootfs=/host'
      - '--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|run|var/lib/docker|host)($$|/)'
    network_mode: host
    pid: host
    volumes:
      - '/:/host:ro,rslave'
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://127.0.0.1:9100/"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
```

the corresponding promscrape.yml config:

```yml
global:
  scrape_interval: 30s
  scrape_timeout: 2s

scrape_configs:
  - job_name: node_exporter
    static_configs:
      - targets: ["host.docker.internal:9100"]
    honor_labels: true
    # If node-exporter has many metrics, use metric_relabel_configs:
    # metric_relabel_configs:
    #   - source_labels: [__name__]
    #     regex: 'node_(cpu|memory|filesystem)_.*'
    #     action: keep  # Only keep CPU, memory, and filesystem metrics

  - job_name: docker_exporter
    static_configs:
      - targets: ["logporter:9333"]
```

# Container metrics collection

There are a lot of options:

* cAdvisor -- most commonly used, but heavyweight. from google.
* https://github.com/dlepaux/docker-exporter -- very very lightweight, written in rust. super small distroless container. unfortunately, it does not support exporting custom container labels.
* https://github.com/davidborzek/docker-exporter -- nice lightweight, written in go. support custom labels, but doesn't export container id. to filter on a label, you are forced to join on the container name, which is not great. 
* https://github.com/Lifailon/logporter -- lightweight container metrics exporter written in go. from graphana. unlike the other lightweight options, it exports container id. but also, it adds labels directly to each metric row (which makes for a bigger database but much easier to filter on multiple labels). as a bonus, can also export logs using Loki API (which victorialogs speaks)

# logporter

If logporter has access to docker images api via the proxy, it will include metrics of when an image is out of date. Currently, we have image access turned off.

an alternative would be Docker Image Update Notifier https://crazymax.dev/diun/

# Vector

Vector is a cool rust-based all-in-one log/metric/trace pipeline processor.

It takes input from a variety of sources, filters them, and then pushes to variety of destinations (or makes data available as an export endpoint).

We have set Vector to push to victoriametrics and victorialogs instead of the normal pull approach.

Vector handles host metrics, host logs, and container logs. It does not handle container metrics natively, so we use logporter for that. We could set it so that logporter metrics are passed through vector, but right now they are directly scraped by victoriametrics.

Test a config:

```sh
docker run --rm \
  -v "$(pwd)/vector.yml:/etc/vector/vector.yaml:ro" \
  timberio/vector:latest-distroless-static \
  validate --no-environment /etc/vector/vector.yaml
``
