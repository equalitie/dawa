Every log record has **fields**. A **stream field** is a special subset of those fields that VictoriaLogs treats as part of the record's *identity* -- a "stream" is the set of records sharing the same values for the configured stream fields.

So:

- **A field** = any key/value on a log record (e.g. `_msg`, `host`, `container_name`, `dc_app`). You can filter on it.
- **A stream field** = a field that is (a) also part of the stream identity, and therefore (b) indexed/grouped by, and (c) queryable as a stream selector.

Container labels are typically fields. We elevate them to be stream fields so they are indexed and we can stream by them.

# Dummy Logs

Dummy host logs:

```sh
while true; do logger -t dummyd -p daemon.err "dummy error $(date -Is)"; sleep 2; done
```

Dummy container logs:

To create a dummy container that simulates logs:

```sh
docker run --rm --name loggen --label dc_app=loggen --label dc_inst=loggen1 kubetail/loggen:0.2.0
```

Or, just use alpine for something even more simple:

```sh
docker run --rm --name dummy-logger --label dc_app=dummy --label dc_env=development --label dc_inst=dummy-1 alpine sh -c 'while true; do echo "$(date -Is) dummy log line $RANDOM"; sleep 1; done'
```
