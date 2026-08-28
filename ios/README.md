# iOS

Person Two owns this SwiftUI client. Open `Plug.xcodeproj`, choose the `Plug` scheme, and run on iOS 17+.

The Phase 0 screen makes a real `GET /health` call and renders connected, failure, loading, service, and environment states. On a physical phone, `localhost` points to the phone; set `localNetwork` in `AppEnvironment.swift` to the Mac's LAN address or use the staging URL.

## Boundaries

- `App` — composition and environment selection
- `Core/Networking` — transport and API models
- `Core/DesignSystem` — reusable tokens/components
- `Core/Models`, `Storage`, `Utilities` — shared client concerns
- `Features` — feature-owned screens and state
- `Resources` — assets and non-secret configuration

Authentication, Ask, Results, Reservation, Activity, NOW, Scout, and Profile directories are boundaries only until their implementation phase begins.
