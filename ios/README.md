# iOS

Person Two owns this SwiftUI client. Open `Plug.xcodeproj`, choose the `Plug` scheme, and run on iOS 17+.

The engineering tab makes a real `GET /health` call and renders connected, failure, loading, service, environment, and correlation ID states. Set `PLUG_API_URL` in the Xcode scheme environment for the real staging HTTPS URL. Release builds require HTTPS and do not fall back to a local or placeholder server.

On a physical phone, `localhost` points to the phone. Use staging for the release checkpoint. The local backend binds only to the Mac's loopback address unless explicitly overridden for a private-network test.

Ask, Activity, Contribute, and Profile tabs establish navigation boundaries; they do not pretend later-phase product functionality exists. Foundation design tokens are provisional pending review of the design handoff.

## Boundaries

- `App` — composition and environment selection
- `Core/Networking` — transport and API models
- `Core/DesignSystem` — reusable tokens/components
- `Core/Models`, `Storage`, `Utilities` — shared client concerns
- `Features` — feature-owned screens and state
- `Resources` — assets and non-secret configuration

Authentication, Ask, Results, Reservation, Activity, NOW, Scout, and Profile directories are boundaries only until their implementation phase begins.
