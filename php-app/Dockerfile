# Build stage: compile PHP extensions
FROM php:8.2-apache-bookworm AS builder

ARG REDIS_EXTENSION_VERSION=6.3.0

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        $PHPIZE_DEPS; \
    docker-php-ext-install -j"$(nproc)" \
        mysqli \
        pdo_mysql; \
    pecl install "redis-${REDIS_EXTENSION_VERSION}"; \
    docker-php-ext-enable redis

# Runtime stage: clean base without build dependencies
FROM php:8.2-apache-bookworm

ARG REDIS_EXTENSION_VERSION=6.3.0

# Install only runtime dependencies
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        curl; \
    rm -rf /var/lib/apt/lists/*

# Copy compiled PHP extensions from builder
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

RUN a2enmod headers rewrite \
    && sed -ri \
        -e 's!^export APACHE_RUN_DIR=.*!export APACHE_RUN_DIR=/tmp/apache2!' \
        -e 's!^export APACHE_LOCK_DIR=.*!export APACHE_LOCK_DIR=/tmp/apache2-lock!' \
        -e 's!^export APACHE_PID_FILE=.*!export APACHE_PID_FILE=/tmp/apache2/apache2.pid!' \
        /etc/apache2/envvars

# Use writable temporary locations so Apache can operate when
# Kubernetes mounts the container root filesystem as read-only.
ENV APACHE_RUN_DIR=/tmp/apache2 \
    APACHE_LOCK_DIR=/tmp/apache2-lock \
    APACHE_PID_FILE=/tmp/apache2/apache2.pid

COPY php-app/apache/ports.conf \
    /etc/apache2/ports.conf

COPY php-app/apache/000-default.conf \
    /etc/apache2/sites-available/000-default.conf

COPY php-app/php.ini \
    /usr/local/etc/php/conf.d/zz-cnas.ini

COPY php-app/*.php \
    /var/www/html/

COPY php-app/assets/ \
    /var/www/html/assets/

COPY php-app/docker-entrypoint.sh \
    /usr/local/bin/cnas-entrypoint

RUN chown -R www-data:www-data /var/www/html \
    && find /var/www/html \
        -type d \
        -exec chmod 0555 {} + \
    && find /var/www/html \
        -type f \
        -exec chmod 0444 {} + \
    && chmod 0555 /usr/local/bin/cnas-entrypoint

WORKDIR /var/www/html

USER www-data

EXPOSE 8080

HEALTHCHECK \
    --interval=30s \
    --timeout=3s \
    --start-period=20s \
    --retries=3 \
    CMD curl --fail --silent --show-error \
        http://127.0.0.1:8080/livez.php \
        || exit 1

ENTRYPOINT ["cnas-entrypoint"]

CMD ["apache2-foreground"]