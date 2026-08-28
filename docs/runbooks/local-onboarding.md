# Clean-checkout onboarding

## Access

1. Accept the GitHub repository invitation.
2. Clone the repository and create a feature branch.
3. Confirm no secrets are stored in the repository.

## Backend lane

1. Install Java 21 and Gradle 8.10+.
2. Run `cd backend && gradle test`.
3. Run `gradle bootRun`.
4. Verify `GET http://localhost:8080/health` and the sample request in the root README.

## iOS lane

1. Install Xcode 16+.
2. Open `ios/Plug.xcodeproj`.
3. Select a development team for local signing.
4. Run `Plug` in a simulator.
5. For a physical phone, replace the placeholder LAN/staging URL in `AppEnvironment.swift`; never commit credentials.

## Before the first shared PR

- Add the second engineer's GitHub username to CODEOWNERS.
- Configure branch protection using `docs/runbooks/repository-protection.md`.
- Agree on the real staging base URL and evidence location.
