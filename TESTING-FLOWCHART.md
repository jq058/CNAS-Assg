# Validation flow

~~~mermaid
flowchart TD
    A[Record Git commit and cluster context] --> B[Lint PHP and run unit tests]
    B --> C[Build and scan immutable image]
    C --> D[Render Compose and Kustomize]
    D --> E[Deploy platform and application]
    E --> F[Check readiness and HTTPS gateway]
    F --> G[Run CRUD smoke test]
    G --> H[Test NetworkPolicy and admission denials]
    H --> I[Run load and observe HPA]
    I --> J[Delete one Pod and measure continuity]
    J --> K[Test backup and isolated restore]
    K --> L[Verify dashboards logs and alerts]
    L --> M[Collect raw output timestamps and hashes]
    M --> N[Redact personal data and cite truthful evidence]
~~~

Use [docs/DEMO-RUNBOOK.md](docs/DEMO-RUNBOOK.md) for the exact commands, expected outcomes, failure rules, and evidence files. A YAML manifest or screenshot alone is not proof that a control worked; retain the command, timestamp, exit code, actual result, and interpretation.
