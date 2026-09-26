# iOS

Person One owns this SwiftUI client (`docs/OWNERSHIP.md`; manual.docx v3 §5 moved iOS out of Person Two's lane because Xcode, signing and TestFlight cannot run on Windows). Open `Plug.xcodeproj`, choose the `Plug` scheme, and run on iOS 17+.

The engineering tab makes a real `GET /health` call and renders connected, failure, loading, service, environment, and correlation ID states. Set `PLUG_API_URL` in the Xcode scheme environment for the real staging HTTPS URL. Release builds require HTTPS and do not fall back to a local or placeholder server.

On a physical phone, `localhost` points to the phone. Use staging for the release checkpoint. The local backend binds only to the Mac's loopback address unless explicitly overridden for a private-network test.

Ask, Activity, Contribute, and Profile tabs establish navigation boundaries; they do not pretend later-phase product functionality exists. Foundation design tokens are provisional pending review of the design handoff.

## Sign in with Apple

`Plug/Resources/Plug.entitlements` declares the capability and is referenced from both
build configurations. Before a build will sign for a physical device, the capability has
to be enabled for App ID `com.abubakarsidiq01.plug.app101` in the Apple Developer portal —
that step is done in a browser, not in this repository, and nobody has done it yet.

Simulator builds sign ad hoc and need nothing from the portal:

```bash
xcodebuild test -project ios/Plug.xcodeproj -scheme Plug \
  -destination 'platform=iOS Simulator,id=YOUR-SIMULATOR-UUID' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

Signing matters for the tests, not just for running: an unsigned build has no entitlement,
the Keychain refuses every call, and `KeychainStoreTests` can only skip.

## Configuration

| Scheme environment variable | What it is |
|---|---|
| `PLUG_API_URL` | The backend. Release builds require `https` and will not fall back. |
| `PLUG_WEB_URL` | Where the public Terms and Privacy pages live. Unset, the consent labels render as plain text rather than as links that go nowhere. |

Tokens live in the Keychain and nowhere else — not `UserDefaults`, not a file, not a log
line, not an analytics property, not a crash breadcrumb. `SessionStore` is the only type
that touches them, and signing out calls the server's revoke endpoint before it clears the
device, because clearing only the device leaves a working session behind.

## Boundaries

- `App` — composition and environment selection
- `Core/Networking` — transport and API models
- `Core/DesignSystem` — reusable tokens/components
- `Core/Models`, `Storage`, `Utilities` — shared client concerns
- `Features` — feature-owned screens and state
- `Resources` — assets and non-secret configuration

Authentication, Ask, Results, Reservation, Activity, NOW, Scout, and Profile directories are boundaries only until their implementation phase begins.
