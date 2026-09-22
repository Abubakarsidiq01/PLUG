# Person One — MacBook setup

If any command here fails on a clean machine, fixing this file is part of the work.

```bash
# 1. Toolchain
xcode-select --install
brew install --cask temurin@21 docker
brew install gh jq node@22 swiftlint
# Gradle is supplied by backend/gradlew. AWS is deferred under ADR-004.
# Xcode from the App Store. Sign in to your Apple Developer account in
# Xcode > Settings > Accounts before Phase 1.

# 2. Repository
gh repo clone Abubakarsidiq01/PLUG
cd PLUG
cp .env.example .env.local        # never commit this
# Set PLUG_DATABASE_PASSWORD to a local-only value in .env.local.
# Add node@22's bin directory to PATH as directed by Homebrew, then:
npm install -g pnpm@9.15.9
npm ci --prefix tools/bruno --ignore-scripts --no-audit --no-fund

# 3. Local data services
set -a
source .env.local
set +a
docker compose --env-file .env.local up -d --wait postgres redis
pnpm install --frozen-lockfile
cd backend
./dev test databaseTest check
# Flyway runs with the db profile; there is no standalone flywayMigrate task.

# 4. Run and verify
./dev bootRun --args='--spring.profiles.active=db'
# Keep that terminal running. Open another terminal at the PLUG repository root:
curl -s localhost:8080/health | jq .

# 5. iOS
open ios/Plug.xcodeproj           # scheme: Plug
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
