# Dawa

dComms Administration Web Application

Dawa is the web interface for managing:

* Users and groups
* Deploying & maintaining containerized applications
* Backups and upgrades
* Server metrics and logging
* OpenID Connect Provider / SSO 

## The container

For now, Dawa is typically distributed as an all-in-one container. Because we don't anticipate
Dawa getting much traffic the database is simply sqlite stored is `/rails/storage` and background job
processing is handled in the main webapp's process tree (SOLID_QUEUE_IN_PUMA=true).

If it is ever the case the Dawa needs to handle more traffic, it would be good to split database and background job processing into separate, specialized containers (or a single container that uses a Procfile to run rails and job processing separately).

## Dummy Data

To create a dummy container that simulates different load conditions:

```sh
docker run --rm --name keep-vm-alive --label dc_app=keepalive gentasumantri/keep-vm-alive
```

## OIDC testing

The nature of OIDC is that the same hostname must resolve to the access the identity provider (Dawa in our case). If you are running Dawa on the host and a test OIDC client in a container, that can be a bit tricky. 

First, edit host's `/etc/hosts` file:

```
127.0.0.1 host.docker.internal
```

Run rails in dev mode bound to 0.0.0.0:

```sh
bin/rails s -b 0.0.0.0
```

Examine configuration:

```sh
curl http://localhost:3000/.well-known/openid-configuration
```

In Dawa, create an SSO app with redirect_uri set to `http://localhost:8080/oauth2/callback`. Then get the values for `client_id` and `client_secret` from Dawa for that app record you just created.

Start a test app with those values:

```sh
docker run \
  --rm \
  --name oidc-client \
  -p 8080:8080 \
  --add-host host.docker.internal:host-gateway \
  authelia/oidc-tester-app \
  oidc-tester-app --issuer http://host.docker.internal:3000 \
                  --id beb7fskOAnXD_urpsthwa0yrGMTqLwcsoleZd6rX76o \
                  --secret khfwZSpfD3WDYv5FZWzAEzZDKjrBKqCZ5jBMJSC75LY
```

This will start a test relaying party / OIDC client at http://localhost:8080.
Load http://localhost:8080 in your browser and click "login". You should be
redirected to http://host.docker.internal:3000 (where Dawa is running), be
presented with a login screen, then redirect back to http://localhost:8080 to
show the authentication confirmation in the test OIDC client.

If oidc-tester-app crashes, try clearing your browser's cookies for localhost:8080 and try again.

If you want to use webauthn for the auth flow, you will need to tell your
browser that host.docker.internal is a secure context. Here is an example for chromium:

```sh
chromium --unsafely-treat-insecure-origin-as-secure="http://host.docker.internal:3000"
```

For the available options:

```sh
docker run --rm authelia/oidc-tester-app oidc-tester-app --help
```

## Building as a Container

Build container:

```sh
docker build --progress=plain -t dawa .
```

Push image to registry: 

```sh
docker login gitlab.equalit.ie
docker tag dawa gitlab.equalit.ie/dcomms/dawa:latest
docker push gitlab.equalit.ie/dcomms/dawa:latest
```

## Running Demo

Set up `.env` file:

```sh
cd container/demo
# generate required env vars:
docker run --rm dawa rake dawa:required > .env
# ensure docker proxy runs with the right group id
# (only needed if docker group id is not the default 984)
echo "DOCKER_GID=`getent group docker | cut -d: -f3`" >> .env
```

Run Dawa:

```sh
cd container/demo
docker-compose up -d
```

## License

TBD
