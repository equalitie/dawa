apt update && apt dist-upgrade
apt install git

curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

git clone https://gitlab.equalit.ie/dcomms/dawa.git
cd dawa
docker build -t dawa .

apt install nginx
apt install snapd
snap install certbot --classic
systemctl stop nginx

certbot certonly --standalone \
  -d demo.dcomms.dev \
  --email elijah@equalitie.org \
  --agree-tos \
  --no-eff-email

curl -s https://raw.githubusercontent.com/certbot/certbot/refs/heads/main/certbot/src/certbot/ssl-dhparams.pem > /etc/letsencrypt/ssl-dhparams.pem

docker run --rm dawa rake dawa:required > .env
echo "DOCKER_GID=`getent group docker | cut -d: -f3`" >> .env

cat > compose.yml << "EOF"
name: dawa_demo
services:
  dawa:
    image: dawa
    container_name: dawa
    ports:
      - "8080:8080"
    environment:
      - RAILS_ENV=production
      - RAILS_LOG_LEVEL=debug
      - DEMO=true
      - DOCKER_URL=http://docker-proxy:2375
      - PUBLIC_PROTOCOL=http
      - SITE_TITLE
      - SITE_DOMAIN
      - SECRET_KEY_BASE
      - SALT
      - OPENID_PRIVATE_KEY
    volumes:
      - dawa_storage:/rails/storage
    deploy:
      resources:
        limits:
          cpus: 1
          memory: 1GB
  docker-proxy:
    image: tecnativa/docker-socket-proxy:latest
    container_name: docker-proxy
    environment:
      - CONTAINERS=1
      - POST=1
      - DELETE=1
      - INFO=1
      - VERSION=1
      - LISTEN=0.0.0.0:2375
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    read_only: true
    tmpfs:
      - /tmp
      - /run
    group_add:
      - "${DOCKER_GID}"
volumes:
  dawa_storage:
EOF

rm /etc/nginx/sites-enabled/default

cat > /etc/nginx/sites-enabled/dawa << "EOF"
upstream dawa {
  server 127.0.0.1:3000;
}

# define $connection_upgrade as either "upgrade" or "close"
# depending on the value of $http_upgrade header
map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}

server {
  server_name demo.dcomms.dev;

  # never redirect to proxied urls
  proxy_redirect off;

  location / {
    try_files $uri @app;
  }

  location @app {
    proxy_pass http://dawa;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
  }
  
  location /cable {
    proxy_pass http://dawa;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;

    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_buffering off;        
    proxy_read_timeout 60s;
    proxy_connect_timeout 60s;
  }

  listen 443 ssl;
  listen [::]:443 ssl ipv6only=on;
  ssl_certificate /etc/letsencrypt/live/demo.dcomms.dev/fullchain.pem; # managed by Certbot
  ssl_certificate_key /etc/letsencrypt/live/demo.dcomms.dev/privkey.pem; # managed by Certbot
  #include /etc/letsencrypt/options-ssl-nginx.conf;
  ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

server {
  listen 80;
  listen [::]:80;
  server_name demo.dcomms.dev;
  return 301 https://$server_name$request_uri;
}
EOF

nginx -t # test configuration
systemctl restart nginx
systemctl status nginx
