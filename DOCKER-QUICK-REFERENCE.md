# Docker quick reference

## Start and inspect

~~~powershell
Copy-Item .env.example .env
# Replace every password placeholder in .env.
docker compose up -d --build
docker compose ps
docker compose logs --tail 100
~~~

Application: http://localhost:8080

Health:

~~~powershell
curl.exe http://localhost:8080/livez.php
curl.exe http://localhost:8080/readyz.php
~~~

## Tests

~~~powershell
docker run --rm --entrypoint sh -v "${PWD}:/workspace:ro" -w /workspace php:8.2-cli-alpine -c "find php-app tests/php -name '*.php' -print0 | xargs -0 -n1 php -l && php tests/php/run.php"
~~~

## Stop

~~~powershell
docker compose down
~~~

Use docker compose down -v only for an intentional clean reset; it removes local database and session data.

For Kubernetes, use [k8s/PLATFORM.md](k8s/PLATFORM.md). For the graded checks, use [docs/DEMO-RUNBOOK.md](docs/DEMO-RUNBOOK.md).
