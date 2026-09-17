# Ownership and collaboration

This follows manual.docx v3, Part I §5, which is controlling. Version 2 of the
manual assigned iOS to Person Two; version 3 does not, because iOS development,
Apple signing, TestFlight and the Simulator cannot run on Windows at all. If any
document, comment or branch in this repository still assigns iOS to Person Two,
it is describing the superseded plan — this file wins.

## Person One — MacBook. Backend, iOS, infrastructure, production. (@Abubakarsidiq01)

Owns `backend/`, `ios/`, `infra/`, `db/`, canonical state, and production and
release ownership. Final technical authority: if a decision conflicts with
something Person Two decided in the web lane, the contract decides, not
seniority.

## Person Two — Windows. Public web, admin console, contracts, fixtures, QA. (@uzom-a)

Owns `web/`, `tests/`, `fixtures/`, `design/`, and external security testing.
Never owns anything requiring macOS — no Xcode, SwiftUI builds, Keychain
implementation, TestFlight, Apple signing or APNs certificates, and no change to
`/backend`, `/ios`, `/infra` or `/db`.

## Shared

Both own `contracts/` and `PROJECT_STATE.json` — both are required reviewers on
every change to either. Neither engineer silently changes the API contract.
Both approvals are required for `contracts/**` and `PROJECT_STATE.json` in
branch protection.

## Collision protocol (manual.docx §26)

1. Create the contract PR first.
2. Freeze missing behavior as a fixture rather than guessing.
3. Work in lane-owned branches, named `<phase>.<step>-<lane>-<short-name>`.
4. If an implementation reveals a contract problem, return to the contract PR.
5. Attach request ID, logs, screenshots, tests, and the `PROJECT_STATE.json`
   update to the integration PR.
