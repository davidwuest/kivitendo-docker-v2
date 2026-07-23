#!/bin/bash
set -e

echo "Starte Initialisierung..."

CONF=/opt/kivitendo-erp/config/kivitendo.conf

# If DB_HOST is provided (e.g. via dev/neon.env), render the
# [authentication/database] section of kivitendo.conf from the environment.
# This keeps credentials out of the tracked kivitendo.conf.
if [ -n "$DB_HOST" ]; then
  echo "Configuring database connection -> ${DB_HOST}:${DB_PORT:-5432}/${DB_NAME}"
  sed -i "/^\[authentication\/database\]/,/^\[/{
    s|^host .*=.*|host     = ${DB_HOST}|
    s|^port .*=.*|port     = ${DB_PORT:-5432}|
    s|^db .*=.*|db       = ${DB_NAME}|
    s|^user .*=.*|user     = ${DB_USER}|
    s|^password .*=.*|password = ${DB_PASSWORD}|
  }" "$CONF"
  # SSL (sslmode=require) and the Neon SNI-fallback (options=endpoint=<id>)
  # are injected directly into the DSN by the build-time patch in the
  # Dockerfile (SL::DBConnect::_connect), so no libpq env vars are needed here.
fi

if [ ! -d webdav ]; then
  mkdir webdav
fi

chown -R www-data users spool webdav

chown -R www-data templates

echo "ServerName localhost" >> /etc/apache2/apache2.conf

# Starte Apache im Vordergrund
exec apachectl -D FOREGROUND
