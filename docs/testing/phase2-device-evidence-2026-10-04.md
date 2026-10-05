# Phase 2 physical-iPhone evidence — 2026-10-04

The paired iPhone (iPhone14,3) ran all six request screenshot walkthroughs against the
synthetic fixture server, reached through the private paired-cable relay. The data is
synthetic; the rendering, text sizes, permissions, gestures and timing are the real device.

## Result

All six passed on the device, at default and largest Dynamic Type:
`testVisualAskHome`, `testRequestStatesDefaultText`, `testRequestStatesLargestText`,
`testBusinessProfilesAndHomeCancellation`, `testDirectSkillEntryWithoutSuggestions`,
`testAnsweredPlaceEvidence`. 60 device screenshots with greyscale copies are in
`evidence/P2/ios/2026-10-04/`. The same six passed on the simulator; screenshots in
`evidence/P2/simulator/2026-10-04/bar-fix/`. iOS unit and integration tests: 67 passed.

## How it was unblocked

Command-line `xcodebuild` could not create the UI-test runner's provisioning profile from the
Xcode 26 Apple Account ("No Accounts"). Building for testing once in Xcode created
`…uitests.xctrunner`; command-line runs use it from then on.

## Bugs the device found, all fixed

The first device runs failed where a tap landed on the bottom navigation instead of the
control under test. Investigation showed real app defects, not slow tests:

1. **Hidden system tab bar still took taps.** `.toolbar(.hidden, for: .tabBar)` was applied to
   the `TabView` itself; SwiftUI applies it from inside each tab. The invisible system bar kept
   its space and hit-testing at the bottom of every page, so a control there could switch tabs.
   It is now hidden from inside each tab.
2. **Page content could stay behind the custom bar.** The bar's reserved space did not reach
   scroll views inside each tab's navigation stack on iOS 26; Profile's Sign out could not
   scroll above it. Every tab now gives its scroll views a bottom content margin (pushed pages
   included) and draws the bar as an overlay.
3. **The bar rode up over the keyboard** and could cover the field being typed in. It now stays
   behind the keyboard like a system tab bar, and its card background reaches the screen edge.
4. **Signing in could bounce the person back to Ask** after they had moved to another tab,
   because the reset ran whenever the signed-in view reappeared. The tab now resets when the
   person signs out, so every sign-in starts on Ask and nothing moves them afterwards.
5. **No way to clear the Ask field.** Earlier words stay after "Ask something else"; the field
   now has a Clear button (44 pt) while it holds text.

Test-only changes: waits after taps allow a real device; the scroll helper treats a control
as reachable only when it is clear of the navigation bar; text entry uses the new Clear button
instead of Select All, which is unreliable at accessibility sizes.

## Still required for G2

VoiceOver walkthrough on the device, an independent design and greyscale review, Person Two's
contract approval and Windows run, the admin vocabulary view, and the joint staging checkpoint
with both signatures.
