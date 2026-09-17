# Infrastructure

Person One owns infrastructure. Phase 0 includes local PostgreSQL/PostGIS configuration and a private staging database Terraform configuration. No Kafka, Kubernetes, or microservices are part of V1.

For Docker-based local setup, export `PLUG_DATABASE_PASSWORD`, then run `docker compose -f infra/compose.yml up -d --wait`. The official `postgis/postgis:16-3.5` image is amd64-only; Compose pins `platform: linux/amd64` so Apple Silicon hosts can pull and run it under emulation. If `docker compose pull` still requests arm64, run `docker pull --platform linux/amd64 postgis/postgis:16-3.5` first. Run `cd backend && ./dev databaseTest` to validate migrations and PostGIS, or `./dev bootRun --args='--spring.profiles.active=db'` to start with database readiness checks.

Staging resources must not be applied until account, region, network, state storage, and cost guardrails are agreed. Never commit secrets or state files. Do not remove the database volume without an explicit backup and approval.

## Secret-storage plan (P0.S6)

Every secret named in `.env.example` follows the same rule locally and in
staging: it is never committed, never pasted into chat, a document, a
screenshot or a fixture, and if it is ever exposed, it is rotated first and
investigated second (manual.docx §1.3, `.env.example`).

| Where | How | Who can read it |
|---|---|---|
| Local development | `.env.local` (gitignored) | Whoever is running the app locally |
| CI | GitHub Actions encrypted secrets (`Settings > Secrets and variables > Actions`) | The workflow only, at run time |
| Staging/production | AWS Secrets Manager, one secret per credential, referenced by ARN from the runtime environment — never baked into an image or a Terraform variable file | The application's IAM role only, via least-privilege policy |
| Database credentials specifically | `aws_db_instance.manage_master_user_password = true` (already set in `infra/terraform/database.tf`) — AWS generates and rotates the master secret; the application uses a separate, narrower runtime role, never the migration user | RDS-managed rotation + the migration role |

Not yet done, because it requires a real AWS account: creating the Secrets
Manager entries themselves, the IAM roles/policies that scope access to them,
and wiring the running application to read `PLUG_JWT_ISSUER`, Twilio and
model-provider credentials (Phase 1+) from Secrets Manager instead of plain
environment variables. That's real provisioning work for whoever holds the
AWS account, not something that can be scaffolded as code with no account to
target.
