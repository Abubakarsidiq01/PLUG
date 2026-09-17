# Person Two — Windows setup

No Apple tooling appears anywhere in this file. If a task seems to need a Mac,
it has been assigned wrongly — raise it rather than working around it.

If any command here fails on a clean machine, fixing this file is part of the work.

```powershell
# 1. Toolchain (first three lines as Administrator)
winget install --id Git.Git -e
winget install --id OpenJS.NodeJS.LTS -e
winget install --id Microsoft.VisualStudioCode -e
winget install --id Docker.DockerDesktop -e
winget install --id EclipseAdoptium.Temurin.21.JDK -e
winget install --id GitHub.cli -e
winget install --id Bruno.Bruno -e
npm install -g pnpm

# 2. WSL2 — required by Docker Desktop, and a better shell for this repo
wsl --install -d Ubuntu

# 3. Repository
gh repo clone <org>/plug
cd plug
Copy-Item .env.example .env.local     # never commit this

# 4. Web
pnpm install
pnpm --filter @plug/web dev            # http://localhost:3000

# 5. Browser tests
pnpm --filter @plug/web exec playwright install
pnpm --filter @plug/web test:e2e

# 6. API collections — no Mac needed, runs against staging
bru run tests/api/health --env staging

# 7. Local data services, when you want the backend running locally
docker compose up -d postgres redis
.\gradlew.bat :backend:bootRun         # reading and running it is fine

# 8. Confirm where you are
Get-Content PROJECT_STATE.json | ConvertFrom-Json |
  Select-Object current_phase, current_step, owner
```

## You own

`/web` `/tests` `/fixtures` `/design` and the web CI workflows.

## You never

Xcode, SwiftUI builds, Keychain implementation, TestFlight, Apple signing, APNs
certificates, production database access, or any change to `/backend`, `/ios`,
`/infra` or `/db`.

## Your six moments in every phase

1. **Contract checkpoint** — before any code. Review fields, errors, states, fixtures.
2. **Design checkpoint** — when the phase has user-facing copy, web UI or supplier messaging.
3. **Independent window** — the long middle. Person One is never blocked by you.
4. **Connected checkpoint** — once, on real staging, side by side.
5. **Release gate** — failure matrix, accessibility, links, security checklist, triage.
6. **Beta operations** — daily, in Phase 7.
