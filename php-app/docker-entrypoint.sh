#!/bin/sh
set -eu

# These paths are writable by the unprivileged Apache process, including when
# /tmp is supplied as a Kubernetes emptyDir or a Compose tmpfs.
mkdir -p /tmp/apache2 /tmp/apache2-lock /tmp/php-sessions

exec "$@"
