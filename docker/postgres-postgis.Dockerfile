FROM debezium/postgres:15-alpine

RUN apk update && apk add --no-cache \
    postgis \
    proj \
    geos \
    gdal \
  && rm -rf /var/cache/apk/*

# No entrypoint change; use upstream entrypoint and healthcheck
