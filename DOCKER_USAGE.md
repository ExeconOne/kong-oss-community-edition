# Kong OSS from Source — Docker Image Guide

## Build the image
```bash
# Without Admin GUI (skips private asset fetch)
DOCKER_BUILDKIT=1 docker build -t kong-oss-community-edition .

# With Admin GUI (pass a GitHub token for gui assets)
DOCKER_BUILDKIT=1 docker build \
  --build-arg GITHUB_TOKEN=$GITHUB_TOKEN \
  -t kong-oss-community-edition .
```

## Run (DB-less) with Admin API + GUI
```bash
docker run --name kong \
  -p 8000:8000 -p 8443:8443 \
  -p 8001:8001 -p 8444:8444 \
  -p 8002:8002 -p 8445:8445 \
  -e KONG_DATABASE=off \
  -e "KONG_ADMIN_LISTEN=0.0.0.0:8001, 0.0.0.0:8444 ssl" \
  -e "KONG_ADMIN_GUI_LISTEN=0.0.0.0:8002, 0.0.0.0:8445 ssl" \
  -e KONG_ADMIN_GUI_API_URL=http://localhost:8001 \
  kong-oss-community-edition
```

## Run with Postgres (DB mode)
```bash
# network + db
docker network create kong-net
docker run -d --name kong-db --network kong-net \
  -e POSTGRES_USER=kong \
  -e POSTGRES_PASSWORD=kongpass \
  -e POSTGRES_DB=kong \
  postgres:15

# migrations (one-time)
docker run --rm --network kong-net \
  -e KONG_DATABASE=postgres \
  -e KONG_PG_HOST=kong-db \
  -e KONG_PG_USER=kong \
  -e KONG_PG_PASSWORD=kongpass \
  -e KONG_PG_DATABASE=kong \
  kong-oss-community-edition kong migrations bootstrap

# start Kong
docker run --name kong \
  --network kong-net \
  -p 8000:8000 -p 8443:8443 \
  -p 8001:8001 -p 8444:8444 \
  -p 8002:8002 -p 8445:8445 \
  -e KONG_DATABASE=postgres \
  -e KONG_PG_HOST=kong-db \
  -e KONG_PG_USER=kong \
  -e KONG_PG_PASSWORD=kongpass \
  -e KONG_PG_DATABASE=kong \
  -e "KONG_ADMIN_LISTEN=0.0.0.0:8001, 0.0.0.0:8444 ssl" \
  -e "KONG_ADMIN_GUI_LISTEN=0.0.0.0:8002, 0.0.0.0:8445 ssl" \
  -e KONG_ADMIN_GUI_API_URL=http://localhost:8001 \
  kong-oss-community-edition
```

## Run with Cassandra (DB mode)
```bash
# network + cassandra
docker network create kong-net
docker run -d --name kong-cassandra --network kong-net \
  -e CASSANDRA_START_RPC=true \
  cassandra:3.11

# wait for Cassandra to be ready (simple pause or proper health check)
sleep 40

# migrations (one-time)
docker run --rm --network kong-net \
  -e KONG_DATABASE=cassandra \
  -e KONG_CASSANDRA_CONTACT_POINTS=kong-cassandra \
  -e KONG_CASSANDRA_PORT=9042 \
  -e KONG_CASSANDRA_KEYSPACE=kong \
  kong-oss-community-edition kong migrations bootstrap

# start Kong
docker run --name kong \
  --network kong-net \
  -p 8000:8000 -p 8443:8443 \
  -p 8001:8001 -p 8444:8444 \
  -p 8002:8002 -p 8445:8445 \
  -e KONG_DATABASE=cassandra \
  -e KONG_CASSANDRA_CONTACT_POINTS=kong-cassandra \
  -e KONG_CASSANDRA_PORT=9042 \
  -e KONG_CASSANDRA_KEYSPACE=kong \
  -e "KONG_ADMIN_LISTEN=0.0.0.0:8001, 0.0.0.0:8444 ssl" \
  -e "KONG_ADMIN_GUI_LISTEN=0.0.0.0:8002, 0.0.0.0:8445 ssl" \
  -e KONG_ADMIN_GUI_API_URL=http://localhost:8001 \
  kong-oss-community-edition
```

## Quick checks
- Healthcheck: `docker inspect --format '{{.State.Health.Status}}' kong`
- Admin API status: `curl -i http://localhost:8001/status`
- Proxy smoke (expect 404): `curl -i http://localhost:8000/`
- GUI: open `http://localhost:8002/` (or `https://localhost:8445/`)

## Verify the ADI Sanction Lists plugin
- Enabled list: `curl -s http://localhost:8001/plugins/enabled | jq '.enabled_plugins'`
- Schema endpoint: `curl -i http://localhost:8001/schemas/plugins/adi-sanction-lists`
- Create a plugin instance (replace config with real values):
  ```bash
  curl -i -X POST http://localhost:8001/plugins \
    --data name=adi-sanction-lists \
    --data "config.<required_field>=<value>"
  ```
- Confirm install: `docker exec kong luarocks show kong-adi-sanction-lists`



## Stop / clean up
```bash
docker stop kong && docker rm kong
```
