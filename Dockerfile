FROM debian:bullseye

LABEL maintainer="your-email@example.com"

# Install dependencies
RUN apt-get update && apt-get install -y \
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
    postgresql libalgorithm-checkdigits-perl libcrypt-pbkdf2-perl git \
    libcgi-pm-perl libtext-unidecode-perl libwww-perl postgresql-contrib \
    poppler-utils libhtml-restrict-perl libdatetime-set-perl \
    libset-infinite-perl liblist-utilsby-perl libdaemon-generic-perl \
    libfile-flock-perl libfile-slurp-perl libfile-mimeinfo-perl \
    libpbkdf2-tiny-perl libregexp-ipv6-perl libdatetime-event-cron-perl \
    libexception-class-perl libxml-libxml-perl libtry-tiny-perl \
    libmath-round-perl libimager-perl libimager-qrcode-perl \
    librest-client-perl libipc-run-perl libencode-imaputf7-perl \
    libmail-imapclient-perl libuuid-tiny-perl locales \
    && rm -rf /var/lib/apt/lists/*

# Install Latex and related tools    
RUN apt-get update && apt-get install -y texlive-base-bin texlive-latex-recommended texlive-fonts-recommended \
    texlive-latex-extra texlive-lang-german ghostscript latexmk


# Set locale
RUN sed -i '/de_DE.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen
ENV LANG de_DE.UTF-8
ENV LANGUAGE de_DE:de
ENV LC_ALL de_DE.UTF-8

WORKDIR /opt

# Clone kivitendo
RUN git clone --depth 1 --branch release-3.9.2 https://github.com/kivitendo/kivitendo-erp.git


WORKDIR /opt/kivitendo-erp

# Apache Konfiguration kopieren
COPY apache-kivitendo.conf /etc/apache2/sites-available/000-default.conf

# Copy Kivitendo configuration
COPY kivitendo.conf /opt/kivitendo-erp/config/kivitendo.conf

# Dispatcher ausführbar machen
RUN chmod +x /opt/kivitendo-erp/dispatcher.fcgi

# Apache mod_fcgid aktivieren
RUN a2enmod fcgid

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

CMD ["/entrypoint.sh"]
