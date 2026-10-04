# ADR-012: Marketplace visual preview

- Status: Temporary owner-requested preview, 2026-10-03. Awaiting the owner's visual feedback.
- Trigger: The owner rated the existing design 2/10, described it as newspaper-like, and
  explicitly rejected the look and navigation. Earlier instructions permit reverting the
  temporary design while preserving functionality.

This preview supersedes ADR-010's visual direction only. The existing ink, paper and neutral
palette remains; the screens use rounded system typography, larger radii, category shortcuts,
photographic category inspiration, and a compact request composer. Uploaded provider images
receive more space on offers. Missing business images are not replaced with generated people.
The illustrative home image is not an actual provider, availability claim, or offer.

Primary navigation is Ask, Activity and Profile, with Inbox for providers. Developer tools
move under Profile in debug builds; the unfinished Contribute placeholder is removed from the
customer tab bar. Activity remains explicit about history not yet being available. Custom
navigation retains selected-state accessibility and keeps the Ask navigation stack alive.

One field still handles both types of ask. Optional business details, truth labels, new-provider
status, direct skill entry, cancellation, and licence requirements are unchanged. Category
shortcuts fill the field; they do not silently submit. No backend or contract changes are needed
for this visual preview. No phase gate is signed off by this work.

Before-preview source snapshots: ignored `output/marketplace-redesign-before/` contains
AskView.swift, ProviderView.swift and PlugApp.swift. Revert those visual changes selectively;
do not undo the earlier direct-skills fix or the owner's other changes.

## Image provenance

Built-in image-generation tool; asset:
`ios/Plug/Resources/Assets.xcassets/ServiceConnection.imageset/service.png`.
Original retained in the Codex generated-images directory. No external runtime image dependency.

Prompt:
> Create a premium natural lifestyle photograph for a local services mobile app category tile.
> Landscape 3:2 composition. A young adult Black woman hair stylist with beautifully braided
> hair wearing a simple charcoal apron, sharing a natural relaxed smile with her adult Black
> woman client with finished long knotless braids in a tasteful small neighborhood salon.
> Realistic candid human connection, believable hands and faces, no posed stock-photo handshake.
> Soft daylight, tactile warm off-white walls, muted sage furnishing, deep charcoal details,
> natural skin tones, restrained colors. Medium shot, faces in upper central half, background
> gently out of focus, no lettering, logos, watermarks, graphic layout, gradients, or UI. This
> represents the hair and beauty category, not a real listed provider. Save image for use as a
> bundled app asset.
