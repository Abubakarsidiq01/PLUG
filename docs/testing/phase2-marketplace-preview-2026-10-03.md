# Marketplace visual preview — 2026-10-03

Temporary visual revision requested after the owner rejected the previous newspaper-like
appearance. See [ADR-012](../decisions/ADR-012-marketplace-visual-preview.md) for scope,
rollback snapshots, image provenance, final asset path and the generation prompt.

Changed the Ask composer, visual service shortcuts, category imagery, provider CTA, offer
cards, uploaded-business photo presentation, provider form heading, Profile header, Activity
empty state and primary navigation. Existing colors remain. Developer tools moved to Profile
(debug only); the unfinished Contribute tab is absent from the main navigation.

Validation:
- Combined simulator flow passed at default and largest text: example filling (without
  submission), provider details/links, switching to Profile and back without losing the
  active ask, direct home cancellation, direct skill entry/save, and suggestion failure.
- 16 synthetic screenshots in `evidence/P2/simulator/2026-10-03/marketplace/`.
- Visual review found oversized custom navigation labels at the largest accessibility size.
  Navigation alone caps its label scale at xxxLarge, exposes full VoiceOver labels and the
  large-content viewer. Screen content continues to use the selected Dynamic Type size.
  Business-link text now aligns leading; the Offer navigation bar uses an opaque surface.
- The targeted business/navigation flow was rerun after those refinements.
- Signed Debug build installed and launched on the paired iPhone. Real device session refresh
  and account load returned HTTP 200 through the existing private paired-only relay.

No backend, API, real-provider data, or matching changes belong to this visual revision.
The checkerboard business image in screenshots is a synthetic upload fixture, not shipped
provider imagery. The new home category image is illustrative and is never used as a fake
provider image. No G2 or joint contract approval is implied.

The paired development relay currently uses `[fd1e:1663:8796::2]:18086` → loopback 18085.
Keep the phone connected and Mac awake. A reconnect can change the private address.
