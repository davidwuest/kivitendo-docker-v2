#!/bin/bash
set -e

echo "Starte Initialisierung..."

CONF=/opt/kivitendo-erp/config/kivitendo.conf

# Database backend switch: "postgres" (local container) or "neon-postgres".
DB_BACKEND="${DB_BACKEND:-postgres}"
echo "Database backend: ${DB_BACKEND}"

if [ "$DB_BACKEND" = "postgres" ]; then
  # Conventional local PostgreSQL container: sensible defaults so the backend
  # works with nothing but DB_BACKEND=postgres set. Any value may be overridden.
  DB_HOST="${DB_HOST:-db}"
  DB_PORT="${DB_PORT:-5432}"
  DB_NAME="${DB_NAME:-kivitendo}"
  DB_USER="${DB_USER:-kivitendo}"
  DB_PASSWORD="${DB_PASSWORD:-kivitendo}"
else
  # neon-postgres (or any external DB): connection details must be provided.
  DB_PORT="${DB_PORT:-5432}"
fi

# Render the [authentication/database] section of kivitendo.conf from the
# environment, keeping credentials out of the tracked kivitendo.conf.
# (For Neon, sslmode=require + the SNI endpoint are injected into the DSN by the
#  build-time SL::DBConnect patch, so no libpq env vars are needed here.)
if [ -n "$DB_HOST" ]; then
  echo "Configuring database connection -> ${DB_HOST}:${DB_PORT}/${DB_NAME}"
  sed -i "/^\[authentication\/database\]/,/^\[/{
    s|^host .*=.*|host     = ${DB_HOST}|
    s|^port .*=.*|port     = ${DB_PORT}|
    s|^db .*=.*|db       = ${DB_NAME}|
    s|^user .*=.*|user     = ${DB_USER}|
    s|^password .*=.*|password = ${DB_PASSWORD}|
  }" "$CONF"
fi

# Override any other kivitendo.conf setting from the environment
# (KIVI_<SECTION>__<KEY>=value). Runs after the DB block above, so a
# KIVI_AUTHENTICATION_DATABASE__* value can still take precedence if set.
perl /usr/local/bin/apply-env-config.pl

# For the local container backend, wait until PostgreSQL accepts connections
# before starting Apache (the db container may still be initialising).
if [ "$DB_BACKEND" = "postgres" ]; then
  echo "Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT} ..."
  for _ in $(seq 1 60); do
    pg_isready -h "$DB_HOST" -p "$DB_PORT" -q && { echo "PostgreSQL is ready."; break; }
    sleep 1
  done
fi

if [ ! -d webdav ]; then
  mkdir webdav
fi

chown -R www-data users spool webdav

chown -R www-data templates

echo "ServerName localhost" >> /etc/apache2/apache2.conf

# Starte Apache im Vordergrund
exec apachectl -D FOREGROUND
