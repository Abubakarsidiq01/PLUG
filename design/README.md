# Design tokens

`tokens.json` is the single source of truth (manual.docx §10.1). Every colour,
size, space, radius and duration in PLUG comes from this file — a hand-typed
hex value or an off-scale spacing number fails review.

## Regenerating

```bash
node design/generate-tokens.mjs
```

Writes `generated/tokens.css` (consumed by `web/`) and `generated/Tokens.swift`
(a `PlugTokens` enum, colours/spacing/radius/motion only — iOS uses system
typography per `tokens.json._rules`, so no type scale is generated for Swift).

Both generated files are committed so CI and a clean clone don't need Node or
Xcode just to read the current token values; regenerate and commit together
whenever `tokens.json` changes.

## Wiring `Tokens.swift` into Xcode

The `Plug` target's `project.pbxproj` references `design/generated/Tokens.swift`
directly — not a copy — so there is exactly one file and regenerating it is
enough; no in-tree file to re-sync. `ios/Plug/Core/DesignSystem/Color+Hex.swift`
(hand-written, not generated — backs the hex literals in `Tokens.swift`) is a
real in-tree file. Both were added via the `xcodeproj` gem, not by hand editing
`project.pbxproj`; `xcodebuild test -scheme Plug` passes with them in place.

Inside `enum PlugTokens { enum Color { ... } }`, colour values must use
`SwiftUI.Color(hex:)`, fully qualified — an unqualified `Color(...)` there
resolves to the nested `PlugTokens.Color` enum itself, not `SwiftUI.Color`,
and fails to compile. The generator already does this; don't hand-edit it away.

`ios/Plug/Core/DesignSystem/PlugTokens.swift` (a different, hand-written
provisional file, `enum PlugColor` / `PlugSpacing` — unfortunate name collision
with the generated `enum PlugTokens`, but they're distinct types and both
compile) still owns the shipped UI until someone deliberately migrates each
usage to the generated `PlugTokens.Color.*` / `PlugTokens.Space.*` — that
migration is a design-review decision, not a mechanical one, so it hasn't been
done automatically here.
