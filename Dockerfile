# syntax=docker/dockerfile:1

########################################
# Stage 1: fetch kivitendo source
# git lives only here, never in the final image (~96 MB saved)
########################################
FROM debian:bullseye-slim AS source

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --depth 1 --branch release-3.9.2 \
      https://github.com/kivitendo/kivitendo-erp.git \
    && rm -rf /opt/kivitendo-erp/.git


########################################
# Stage 2: runtime image
########################################
FROM debian:bullseye-slim

LABEL maintainer="your-email@example.com"

# Runtime dependencies: Apache, Perl modules and the PostgreSQL *client*.
# The database itself runs in a separate container (see docker-compose.yml),
# so the full postgresql server + contrib are NOT installed here.
RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2 libapache2-mod-fcgid \
    libarchive-zip-perl libclone-perl \
    libconfig-std-perl libdatetime-perl libdbd-pg-perl libdbi-perl \
    libemail-address-perl libemail-mime-perl libfcgi-perl libjson-perl \
    liblist-moreutils-perl libnet-smtp-ssl-perl libnet-sslglue-perl \
    libparams-validate-perl libpdf-api2-perl librose-db-object-perl \
    librose-db-perl librose-object-perl libsort-naturally-perl \
    libstring-shellquote-perl libtemplate-perl libtext-csv-xs-perl \
    libtext-iconv-perl liburi-perl libxml-writer-perl libyaml-perl \
    libimage-info-perl libgd-gd2-perl libfile-copy-recursive-perl \
    postgresql-client libalgorithm-checkdigits-perl libcrypt-pbkdf2-perl \
    libcgi-pm-perl libtext-unidecode-perl libwww-perl \
    poppler-utils libhtml-restrict-perl libdatetime-set-perl \
    libset-infinite-perl liblist-utilsby-perl libdaemon-generic-perl \
    libfile-flock-perl libfile-slurp-perl libfile-mimeinfo-perl \
    libpbkdf2-tiny-perl libregexp-ipv6-perl libdatetime-event-cron-perl \
    libexception-class-perl libxml-libxml-perl libtry-tiny-perl \
    libmath-round-perl libimager-perl libimager-qrcode-perl \
    librest-client-perl libipc-run-perl libencode-imaputf7-perl \
    libmail-imapclient-perl libuuid-tiny-perl libcryptx-perl locales \
    && rm -rf /var/lib/apt/lists/*

# LaTeX toolchain for PDF generation.
# --no-install-recommends skips the huge texlive-*-doc packages (~500 MB)
# while keeping full LaTeX functionality.
RUN apt-get update && apt-get install -y --no-install-recommends \
    texlive-latex-recommended texlive-fonts-recommended \
    texlive-latex-extra texlive-plain-generic texlive-lang-german \
    ghostscript latexmk \
    && rm -rf /var/lib/apt/lists/*

# Set locale
RUN sed -i '/de_DE.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen
ENV LANG=de_DE.UTF-8
ENV LANGUAGE=de_DE:de
ENV LC_ALL=de_DE.UTF-8

WORKDIR /opt/kivitendo-erp

# Kivitendo source from the build stage (without .git history)
COPY --from=source /opt/kivitendo-erp /opt/kivitendo-erp

# Neon compatibility patches (DSN sslmode/endpoint injection + accepting a
# CREATEDB role for dataset creation). See the script header for rationale.
# Both are inert/safe for a normal or local PostgreSQL.
COPY docker/patch-neon-compat.pl /tmp/patch-neon-compat.pl
RUN perl /tmp/patch-neon-compat.pl \
    && perl -c -I/opt/kivitendo-erp /opt/kivitendo-erp/SL/DBConnect.pm \
    && perl -c -I/opt/kivitendo-erp /opt/kivitendo-erp/SL/DBUtils.pm \
    && perl -c -I/opt/kivitendo-erp /opt/kivitendo-erp/SL/Controller/Admin.pm \
    && perl -c -I/opt/kivitendo-erp /opt/kivitendo-erp/SL/User.pm \
    && rm /tmp/patch-neon-compat.pl

# Apache Konfiguration kopieren
COPY apache-kivitendo.conf /etc/apache2/sites-available/000-default.conf

# Copy Kivitendo configuration
COPY kivitendo.conf /opt/kivitendo-erp/config/kivitendo.conf

# Dispatcher ausführbar machen + Apache mod_fcgid aktivieren
RUN chmod +x /opt/kivitendo-erp/dispatcher.fcgi && \
    a2enmod fcgid

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

CMD ["/entrypoint.sh"]
