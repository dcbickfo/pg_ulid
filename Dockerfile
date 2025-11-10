# Multi-stage Dockerfile for building pg_ulid extension
# Supports PostgreSQL 12-18
# Build: docker build --build-arg PG_VERSION=18 -t postgres-pg_ulid:18 .
# Usage: docker run -d -p 5432:5432 postgres-pg_ulid:18

ARG PG_VERSION=18
FROM postgres:${PG_VERSION} AS build

# Install build dependencies for all PostgreSQL versions
RUN apt-get update && apt-get -y upgrade \
    && apt-get install -y build-essential libpq-dev postgresql-server-dev-all

WORKDIR /srv
COPY . /srv

# Build extension using PGXS (supports all PostgreSQL versions)
RUN make PG_CONFIG=/usr/lib/postgresql/${PG_MAJOR}/bin/pg_config

# Create distribution tarball and checksums
RUN TARGETS=ulid.so \
  && tar -czvf pg_ulid.tar.gz $TARGETS pg_ulid--0.1.0.sql pg_ulid.control \
  && sha256sum pg_ulid.tar.gz $TARGETS pg_ulid--0.1.0.sql pg_ulid.control > SHA256SUMS

ARG PG_VERSION=18
FROM postgres:${PG_VERSION} AS deploy

# Copy tarball and checksums
COPY --from=build /srv/pg_ulid.tar.gz /srv/SHA256SUMS /srv/

# Install extension to PostgreSQL
COPY --from=build /srv/ulid.so /usr/lib/postgresql/${PG_MAJOR}/lib
COPY --from=build /srv/pg_ulid.control /usr/share/postgresql/${PG_MAJOR}/extension
COPY --from=build /srv/pg_ulid--0.1.0.sql /usr/share/postgresql/${PG_MAJOR}/extension