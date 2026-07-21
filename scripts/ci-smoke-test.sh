#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-cnas}"
SERVICE_URL="${SERVICE_URL:-http://php-service.cnas.svc.cluster.local}"
GATEWAY_URL="${GATEWAY_URL:-https://kong-gateway-proxy.kong.svc.cluster.local}"
GATEWAY_HOST="${GATEWAY_HOST:-cnas.local}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-180s}"

for command in kubectl date; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command not found: ${command}" >&2
    exit 2
  }
done

kubectl -n "${NAMESPACE}" rollout status deployment/php-app --timeout="${ROLLOUT_TIMEOUT}"
kubectl -n "${NAMESPACE}" rollout status statefulset/mysql --timeout="${ROLLOUT_TIMEOUT}"

suffix="$(date -u +%Y%m%d%H%M%S)-${BUILD_NUMBER:-0}"
suffix="$(printf '%s' "${suffix}" | tr -cd 'a-zA-Z0-9-')"
job_name="cnas-ci-smoke-${suffix,,}"
job_name="${job_name:0:63}"
test_name="CnasCi${suffix//-/}"
test_email="cnas-ci-${suffix}@example.invalid"
updated_email="cnas-ci-updated-${suffix}@example.invalid"

cleanup() {
  kubectl -n "${NAMESPACE}" delete job "${job_name}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: cnas-ci-smoke
    app.kubernetes.io/part-of: cnas-validation
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 180
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: cnas-ci-smoke
        app.kubernetes.io/part-of: cnas-validation
        access-profile: validation
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 100
        runAsGroup: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: smoke
          image: curlimages/curl:8.12.1
          imagePullPolicy: IfNotPresent
          env:
            - name: SERVICE_URL
              value: "${SERVICE_URL}"
            - name: GATEWAY_URL
              value: "${GATEWAY_URL}"
            - name: GATEWAY_HOST
              value: "${GATEWAY_HOST}"
            - name: TEST_NAME
              value: "${test_name}"
            - name: TEST_EMAIL
              value: "${test_email}"
            - name: UPDATED_EMAIL
              value: "${updated_email}"
          command: ["/bin/sh", "-ec"]
          args:
            - |
              service_base="\${SERVICE_URL%/}"
              base="\${GATEWAY_URL%/}"
              cookies=/tmp/cookies.txt

              curl_app() {
                curl --insecure -H "Host: \${GATEWAY_HOST}" "\$@"
              }

              extract_csrf() {
                tr '\n' ' ' < "\$1" | sed -n "s/.*name=['\"']csrf_token['\"'][^>]*value=['\"']\([^'\"']*\)['\"'].*/\1/p"
              }

              echo "[health] application Service"
              curl -fsS --max-time 10 "\${service_base}/readyz.php" > /tmp/service.html
              grep -q "ready" /tmp/service.html

              echo "[health] Gateway API route"
              curl -fsSk --max-time 10 -H "Host: \${GATEWAY_HOST}" "\${GATEWAY_URL}" > /tmp/gateway.html
              grep -q "Team Members" /tmp/gateway.html

              echo "[create] unique test member"
              curl_app -fsS -c "\${cookies}" "\${base}/create.php" > /tmp/create-form.html
              create_csrf="\$(extract_csrf /tmp/create-form.html)"
              set -- -d "name=\${TEST_NAME}" -d "email=\${TEST_EMAIL}"
              if [ -n "\${create_csrf}" ]; then
                set -- "\$@" -d "csrf_token=\${create_csrf}"
              fi
              curl_app -fsS -b "\${cookies}" -c "\${cookies}" -o /dev/null "\$@" -X POST "\${base}/create.php"

              curl_app -fsS -b "\${cookies}" "\${base}/" > /tmp/read.html
              grep -q "\${TEST_EMAIL}" /tmp/read.html
              row="\$(tr '\n' ' ' < /tmp/read.html | sed 's#</tr>#</tr>\n#g' | grep -F "\${TEST_EMAIL}" | head -n 1)"
              id="\$(printf '%s' "\${row}" | sed -n 's#.*update.php?id=\([0-9][0-9]*\).*#\1#p')"
              test -n "\${id}"
              echo "Created id=\${id}"

              echo "[update] test member"
              curl_app -fsS -b "\${cookies}" -c "\${cookies}" "\${base}/update.php?id=\${id}" > /tmp/update-form.html
              update_csrf="\$(extract_csrf /tmp/update-form.html)"
              set -- -d "name=\${TEST_NAME}Updated" -d "email=\${UPDATED_EMAIL}"
              if [ -n "\${update_csrf}" ]; then
                set -- "\$@" -d "csrf_token=\${update_csrf}"
              fi
              curl_app -fsS -b "\${cookies}" -c "\${cookies}" -o /dev/null "\$@" -X POST "\${base}/update.php?id=\${id}"
              curl_app -fsS -b "\${cookies}" "\${base}/" > /tmp/updated.html
              grep -q "\${UPDATED_EMAIL}" /tmp/updated.html

              echo "[delete] test member"
              deleted=false
              attempt=1
              while [ "\${attempt}" -le 15 ]; do
                curl_app -fsS -b "\${cookies}" -c "\${cookies}" "\${base}/" > /tmp/delete-form.html
                csrf="\$(extract_csrf /tmp/delete-form.html)"
                test -n "\${csrf}"
                status="\$(curl_app -sS -o /tmp/delete-response.html -w '%{http_code}' \
                  -b "\${cookies}" -c "\${cookies}" -X POST \
                  -d "id=\${id}" -d "csrf_token=\${csrf}" "\${base}/delete.php")"
                case "\${status}" in
                  2*|3*) deleted=true; break ;;
                  403) attempt=\$((attempt + 1)); sleep 1 ;;
                  *) echo "Unexpected delete status \${status}"; cat /tmp/delete-response.html; exit 1 ;;
                esac
              done
              test "\${deleted}" = true
              curl_app -fsS "\${base}/" > /tmp/final.html
              if grep -q "\${UPDATED_EMAIL}" /tmp/final.html; then
                echo "Delete did not remove the test record"
                exit 1
              fi

              echo "PASS: Service/gateway health and create/read/update/delete checks succeeded."
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              cpu: 200m
              memory: 96Mi
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir:
            sizeLimit: 32Mi
EOF

if ! kubectl -n "${NAMESPACE}" wait --for=condition=complete "job/${job_name}" --timeout=180s; then
  kubectl -n "${NAMESPACE}" logs "job/${job_name}" --all-containers=true || true
  kubectl -n "${NAMESPACE}" describe "job/${job_name}" || true
  exit 1
fi

kubectl -n "${NAMESPACE}" logs "job/${job_name}" --all-containers=true
echo "CI smoke test passed."
