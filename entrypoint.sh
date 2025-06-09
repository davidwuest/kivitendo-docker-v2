#!/bin/bash
set -e

# Beispiel: Dein Shell-Skript
echo "Starte Initialisierung..."

if [ ! -d webdav ]; then
  mkdir webdav
fi

chown -R www-data users spool webdav

echo "ServerName localhost" >> /etc/apache2/apache2.conf

# Starte Apache im Vordergrund
exec apachectl -D FOREGROUND

echo "Ready..."