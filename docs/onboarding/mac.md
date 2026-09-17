# Person One — MacBook setup

If any command here fails on a clean machine, fixing this file is part of the work.

```bash
# 1. Toolchain
xcode-select --install
brew install --cask temurin@21 docker
brew install gradle awscli terraform postgresql@16 gh jq
# Xcode from the App Store. Sign in to your Apple Developer account in
# Xcode > Settings > Accounts before Phase 1.

# 2. Repository
gh repo clone <org>/plug && cd plug
cp .env.example .env.local        # never commit this

# 3. Local data services
docker compose up -d postgres redis
./gradlew :backend:flywayMigrate

# 4. Run and verify
./gradlew :backend:bootRun        # http://localhost:8080
curl -s localhost:8080/health | jq .

# 5. iOS
open ios/PLUG.xcodeproj           # scheme: PLUG-Staging
# Run on a REAL device before the end of Phase 0. The Simulator hides real
# network behaviour, and Phase 0's whole purpose is proving that path.

# 6. Confirm where you are
cat PROJECT_STATE.json | jq '{current_phase, current_step, owner}'
```

## You own

`/backend` `/ios` `/infra` `/db` and the backend and iOS CI workflows.

## Only you can

- Build, sign and upload a TestFlight build
- Apply a migration to staging or production
- Change Terraform, IAM, WAF, KMS or secrets
- Approve anything under `/backend/src/main/java/app/plug/security`
- Declare a production release or execute a rollback
