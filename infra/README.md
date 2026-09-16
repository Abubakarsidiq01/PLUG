# Infrastructure

Person One owns infrastructure. Phase 0 includes local PostgreSQL/PostGIS configuration and a private staging database Terraform configuration. No Kafka, Kubernetes, or microservices are part of V1.

For Docker-based local setup, export `PLUG_DATABASE_PASSWORD`, then run `docker compose -f infra/compose.yml up -d --wait`. The official `postgis/postgis:16-3.5` image is amd64-only; Compose pins `platform: linux/amd64` so Apple Silicon hosts can pull and run it under emulation. If `docker compose pull` still requests arm64, run `docker pull --platform linux/amd64 postgis/postgis:16-3.5` first. Run `cd backend && ./dev databaseTest` to validate migrations and PostGIS, or `./dev bootRun --args='--spring.profiles.active=db'` to start with database readiness checks.

Staging resources must not be applied until account, region, network, state storage, and cost guardrails are agreed. Never commit secrets or state files. Do not remove the database volume without an explicit backup and approval.
