# Person Two — Windows setup

No Apple tooling appears anywhere in this file. If a task seems to need a Mac,
it has been assigned wrongly — raise it rather than working around it.

If any command here fails on a clean machine, fixing this file is part of the work.

```powershell
# 1. Toolchain (first line as Administrator; winget may prompt for a restart
# after Docker Desktop — finish it before continuing)
winget install --id Git.Git -e
# Install Node.js 22.x (22.13 or newer) from https://nodejs.org/en/download
# to match CI. Do not select a different major just because it is the latest LTS.
winget install --id Microsoft.VisualStudioCode -e
winget install --id Docker.DockerDesktop -e
winget install --id EclipseAdoptium.Temurin.21.JDK -e
winget install --id GitHub.cli -e
winget install --id Bruno.Bruno -e   # the GUI app — optional, for browsing requests
# Close and reopen the terminal after the tool installations so PATH refreshes.
# Confirm node --version shows v22.x and java -version shows JDK 21, then:
npm install -g pnpm@9.15.9

# 2. WSL2 — required by Docker Desktop, and a better shell for this repo
wsl --install -d Ubuntu
# Open Docker Desktop once and wait for "Docker Desktop is running" before step 6.

# 3. Repository
gh repo clone Abubakarsidiq01/PLUG
cd PLUG
npm ci --prefix tools/bruno --ignore-scripts --no-audit --no-fund
Copy-Item .env.example .env.local     # never commit this
# Open .env.local and set PLUG_DATABASE_PASSWORD to any local-only value.

# 4. Web
pnpm install
pnpm --filter @plug/web dev            # http://localhost:3000 — Ctrl+C when done looking

# 5. Browser tests
pnpm --filter @plug/web exec playwright install
pnpm --filter @plug/web test:e2e

# 6. Local data services + backend (no Mac needed to run or read this)
$env:PLUG_DATABASE_PASSWORD = "<the value you put in .env.local>"
docker compose -f infra/compose.yml up -d --wait
# Person Two observed a TLS error on the first image pull; one retry succeeded.
# Root cause is unconfirmed. If it repeats, check Docker Desktop network/proxy
# settings and collect the error; do not disable TLS verification.
cd backend
.\gradlew.bat bootRun --args="--spring.profiles.active=db"
# Leave this running in its own terminal; open a new one for step 7.

# 7. API collections — open a new terminal at the PLUG repository root
Push-Location tests/api
& "../../tools/bruno/node_modules/.bin/bru.cmd" run --env local
Pop-Location
# There is no standing staging URL while ADR-004 is in effect.
# For the live tunnel, follow ADR-004's public-only collection command; readiness
# is private. A tunnel uses the local validation stub, not the JWT staging profile.

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
