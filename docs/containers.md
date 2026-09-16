# Ports

* dawa:3000
* docker-proxy:2375
* victoriametrics:8428
* victorialogs:9428 
* node-exporter: host.docker.internal:9100 
* docker-exporter:8080

# Docker Proxy

**linuxserver/socket-proxy**

- Image: lscr.io/linuxserver/socket-proxy:latest
- Repository: https://github.com/linuxserver/docker-socket-proxy
- Pros: Well-maintained by the LinuxServer.io team, a trusted open-source group. fork of tecnativa/docker-socket-proxy. Offers a very granular set of environment variables for fine-tuning, including specific GET-only options (ALLOW_LOGS, ALLOW_TOP) and lifecycle controls (ALLOW_START, ALLOW_STOP) that work even in read-only (POST=0) mode. Provides dedicated support for Podman/libpod API through separate LIBPOD_* variables.
- Cons: Permissions are global. They apply to the entire proxy instance, so all clients connected to it share the same access level. This makes it impossible to give different permissions to different clients (e.g., read-only for one, write for another) without running multiple proxy instances.

**cerede2000/docker-socket-proxy**

- Image: cerede2000/docker-socket-proxy:latest or ghcr.io/cerede2000/docker-socket-proxy:latest
- Repository: https://github.com/cerede2000/docker-socket-proxy
- Pros: Per-client permission profiles are its defining feature. Each client container gets a socketproxy.role label, and the proxy assigns permissions based on that role. This allows fine-grained control, such as giving Traefik read-only access while allowing a management UI to restart only a specific container. Offers scoped permissions, meaning you can restrict a client's access to a specific set of containers using allowlist, blacklist, or per-container exceptions (container_rules). Built in Go and runs as a non-root user on a minimal distroless image.
- Cons: A newer, single-person project. Its security model and configuration (via a profiles.yml file) are more complex to set up compared to simpler environment-variable-based proxies.

**swiftwave-org/docker-socket-proxy**

- Repository: https://github.com/swiftwave-org/docker-socket-proxy
- Pros: Provides separate read and write permissions for each API endpoint (e.g., CONTAINERS_READ, CONTAINERS_WRITE), offering a more granular global control model. This makes it easier to grant read-only access to some endpoints while allowing writes on others without a blunt POST=0 toggle.
- Cons: Permissions are global, applied to all clients connecting to the proxy instance. Does not offer per-client profiles like cerede2000/docker-socket-proxy.

**tecnativa/docker-socket-proxy**

- Image: tecnativa/docker-socket-proxy:latest
- Repository: https://github.com/Tecnativa/docker-socket-proxy
- Pros: The original and most popular socket proxy, well-established and battle-tested. It serves as the conceptual base for the LinuxServer.io fork. Simple, mature project that is effectively HAProxy with a custom configuration file.
- Cons: Permissions are global, with a simpler POST and API family-based control model. The LinuxServer fork offers more granularity with its ALLOW_* variables. The project has not seen significant updates recently.

# TODO

## node exporter

Currently, node-exporter is run in host mode so it can access the
hosts networking information. This means that then victoriametrics needs
to be configured with host.docker.internal.

It also means that node-exporter is exposed publicly and a firewall has to be
set up to prevent public access to all the node-exporter data.

This is not ideal, because it is always better to rely solely on the firewall
rules.

This alternate might work:

```
volumes:
  - /proc/net:/host/proc/net:ro
```

I have not gotten this working.

## docker exporter

currently replaced by logporter

```yml
docker-exporter gathers metrics for all the containers.
docker-exporter:
  image: ghcr.io/davidborzek/docker-exporter:latest
  container_name: docker-exporter
  restart: unless-stopped
  expose:
    - 8080
  environment:
    DOCKER_HOST: "http://docker-proxy:2375"
    DOCKER_EXPORTER_PORT: "8080"
    DOCKER_EXPORTER_LOG_LEVEL: "info"
    DOCKER_EXPORTER_IGNORE_LABEL: "docker-exporter.ignore"
    #DOCKER_EXPORTER_CONTAINER_LABELS: "dcomms_app,dcomms_container,dcomms_instance,dcomms_version,dcomms_internal"
    DOCKER_EXPORTER_CONTAINER_LABELS: "dcomms_app"
```
