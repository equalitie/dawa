# Dawa

dComms Administration Web Application

Dawa is the web interface for managing:

* Users and groups
* Deploying & maintaining containerized applications
* Server metrics and logging
* SSO 

## Installation

## Usage


## Dummy Data

To create a dummy container that simulates different load conditions:

```sh
docker run -d --name keep-vm-alive gentasumantri/keep-vm-alive
```

To create a dummy container that simulates logs:

```sh
docker run -d --name loggen kubetail/loggen:0.2.0
```

## Support

## Roadmap

## Contributing

## Links

* Node Exporter: used to gather statistics for the host. https://github.com/prometheus/node_exporter

## License
