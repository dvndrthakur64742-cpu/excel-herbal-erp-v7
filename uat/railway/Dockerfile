FROM wordpress:php8.3-apache

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends mariadb-client; \
    if ! command -v mysqlcheck >/dev/null 2>&1; then ln -s "$(command -v mariadb-check)" /usr/local/bin/mysqlcheck; fi; \
    command -v mysqlcheck; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    for module in /etc/apache2/mods-enabled/mpm_*.load; do \
      [ -e "$module" ] || continue; \
      name="${module##*/}"; \
      name="${name%.load}"; \
      if [ "$name" != "mpm_prefork" ]; then a2dismod "$name"; fi; \
    done; \
    a2enmod mpm_prefork; \
    mpm_count="$(find /etc/apache2/mods-enabled -maxdepth 1 -name 'mpm_*.load' | wc -l)"; \
    test "$mpm_count" -eq 1


RUN set -eux; \
    curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp; \
    chmod +x /usr/local/bin/wp

COPY backend/excel-herbal-erp-v7 /usr/src/wordpress/wp-content/plugins/excel-herbal-erp-v7
COPY uat/railway/eh7-uat-entrypoint.sh /usr/local/bin/eh7-uat-entrypoint

RUN chmod +x /usr/local/bin/eh7-uat-entrypoint

ENTRYPOINT ["/usr/local/bin/eh7-uat-entrypoint"]
CMD ["apache2-foreground"]
