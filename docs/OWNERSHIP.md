# Ownership and collaboration

## Person One — backend and systems

Owns `backend/`, `infra/`, canonical state, backend logs, and provider-side contract checks. Person Two may run these locally and contribute reviewed fixes.

## Person Two — iOS and product

Owns `ios/`, navigation, SwiftUI presentation, accessibility, client diagnostics, and consumer-side decoding checks. Person One may review networking and debugging paths.

## Shared

Both own `contracts/`, `fixtures/`, `docs/`, end-to-end testing, metrics, and checkpoint evidence. Neither engineer silently changes the API contract.

The current CODEOWNERS uses `@Abubakarsidiq01` because the second engineer's GitHub username is not yet known. Add that username to `.github/CODEOWNERS` immediately after the collaborator accepts the invitation, then require both approvals for `contracts/**` in branch protection.

## Collision protocol

1. Create the contract PR first.
2. Freeze missing behavior as a fixture rather than guessing.
3. Work in lane-owned branches.
4. If an implementation reveals a contract problem, return to the contract PR.
5. Attach request ID, logs, screenshots, tests, and final state to the integration PR.
