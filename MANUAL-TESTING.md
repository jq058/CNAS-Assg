# Manual testing

This short page covers the local application check. The authoritative Kubernetes validation, evidence, scaling, resilience, policy, monitoring, alert, and backup/restore procedures are in [docs/DEMO-RUNBOOK.md](docs/DEMO-RUNBOOK.md).

## Local application

1. Copy .env.example to .env.
2. Replace every password placeholder with a unique long random value.
3. Start the stack and wait until all three services are healthy.

~~~powershell
docker compose up -d --build
docker compose ps
~~~

Open http://localhost:8080.

### Create

Add a member with a valid name and email. Confirm the new row appears.

### Validation and duplicate handling

Try an empty name, an invalid email, and the same email twice. Confirm the form shows a friendly error and does not create an invalid or duplicate row.

### Update

Edit the test member. Confirm the ID remains the same and the new values appear.

### Delete

Delete the member using the confirmation control. Confirm the row is removed.

### Security behavior

These checks should not expose sensitive error details:

- directly browse to database.php, db.php, functions.php, or session_store.php and expect HTTP 403;
- request an unknown path and expect the custom HTTP 404 page;
- submit a mutation without the current CSRF token and expect HTTP 403;
- inspect the response headers for Content-Security-Policy, X-Content-Type-Options, and Referrer-Policy.

### Health and persistence

~~~powershell
curl.exe -i http://localhost:8080/livez.php
curl.exe -i http://localhost:8080/readyz.php
docker compose down
docker compose up -d
docker compose ps
~~~

The member data should survive because MySQL uses a named volume. The readiness endpoint should return success only when MySQL and Redis are reachable.

### Automated checks

~~~powershell
docker run --rm --entrypoint sh -v "${PWD}:/workspace:ro" -w /workspace php:8.2-cli-alpine -c "find php-app tests/php -name '*.php' -print0 | xargs -0 -n1 php -l && php tests/php/run.php"
~~~

## Kubernetes and marking evidence

Follow these documents in order:

1. [k8s/PLATFORM.md](k8s/PLATFORM.md) to create and deploy the safe Kind profile.
2. [docs/DEMO-RUNBOOK.md](docs/DEMO-RUNBOOK.md) to run repeatable checks and collect truthful evidence.
3. [docs/CI-CD.md](docs/CI-CD.md) to configure and demonstrate Jenkins traceability.

Do not use old nginx Ingress, committed Secret, phpMyAdmin, latest-tag, or hardcoded-password instructions; those are not part of the current design.
