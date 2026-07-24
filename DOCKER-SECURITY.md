# Docker security

The application image applies these controls:

- Apache/PHP runs as www-data on unprivileged port 8080.
- The image copies only runtime PHP, asset, and configuration files.
- Build-only compiler packages are in the builder stage only; the runtime stage is clean.
- Application files are read-only and internal PHP modules are denied by Apache.
- The web root filesystem is read-only with a small writable tmpfs.
- Redis requires authentication and stores shared sessions.
- MySQL and Redis are not published to host ports.
- Mutation endpoints require POST plus CSRF validation; SQL uses prepared statements.
- Browser responses include CSP and related security headers.

Build and test:

~~~powershell
docker build -t cnas-php-app:local .
docker run --rm --entrypoint sh -v "${PWD}:/workspace:ro" -w /workspace cnas-php-app:local -c "find php-app tests/php -name '*.php' -print0 | xargs -0 -n1 php -l && php tests/php/run.php"
~~~

The Kubernetes profile adds restricted Pod Security, read-only filesystems, resource limits, default-deny NetworkPolicy, Kyverno admission policy, TLS through Kong, and CI vulnerability scanning. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
