FROM wordpress:php8.3-apache

RUN set -eux; \
    curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp; \
    chmod +x /usr/local/bin/wp

COPY backend/excel-herbal-erp-v7 /usr/src/wordpress/wp-content/plugins/excel-herbal-erp-v7
COPY uat/railway/eh7-uat-entrypoint.sh /usr/local/bin/eh7-uat-entrypoint

RUN chmod +x /usr/local/bin/eh7-uat-entrypoint

ENTRYPOINT ["/usr/local/bin/eh7-uat-entrypoint"]
CMD ["apache2-foreground"]
