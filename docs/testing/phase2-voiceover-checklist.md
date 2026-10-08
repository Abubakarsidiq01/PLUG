# VoiceOver walkthrough — Phase 2 (owner, on the iPhone)

> **Status:** not required for G2. The owner excepted it on 8 October 2026; the automated
> accessibility audit is the mitigation, and this pass is due before any public release
> (`docs/testing/phase2-g2-exceptions.md`). Kept here for that pass.

The manual requires a recorded VoiceOver pass of the primary flow (§12.3, evidence/P2/a11y).
The automated audit (`evidence/P2/a11y/<date>/automated-accessibility-audit.txt`) covers
contrast, hit areas, clipping and labels; this pass proves the flow is usable by ear.

**Setup:** run `sh tools/run-phase2-phone.sh`. On the iPhone: Settings → Accessibility →
VoiceOver → on (or triple-click the side button if the shortcut is set). Start a screen
recording from Control Center with the microphone **on**, so the speech is captured.

Gestures: swipe right/left = next/previous item, double-tap = activate, two-finger swipe up =
read all, three-finger swipe = scroll.

Tick each item and note anything read wrongly, out of order, or skipped.

1. ☐ Welcome: "Continue as guest" is announced as a button; double-tap it.
2. ☐ Ask home: the title, the field ("What do you need?"), Ask, Voice, the four shortcuts
   (Hair & beauty, Home help, Tech, Places) and "Offer a service" are each announced once,
   in screen order. The photo tile is announced by its purpose, not the picture.
3. ☐ Double-tap a shortcut: the field now holds the example text (VoiceOver reads it) and
   nothing was sent.
4. ☐ Type "Barber under $35" with the keyboard; double-tap Ask; allow location when asked.
5. ☐ Waiting: "Asking barber nearby", then Notified / Replied / Offers each with their number.
6. ☐ Results: "Meet your options"; each filter (For you, Lowest price, Closest) says
   "selected" when chosen; each offer reads business, New provider, service, price and its
   label (Estimated) as one sensible unit; View details is a button.
7. ☐ Offer detail: business first, then service, price, label, Earliest, Away, location,
   expiry. The demo notice is read.
8. ☐ Two-finger scrub (Z gesture) goes back.
9. ☐ Stop asking: announced as a button; after it, "You stopped asking" is read.
10. ☐ Bottom navigation: Ask, Activity, Profile (and Inbox once offering a service) are
    buttons; the current one says "selected". With very large text, press and hold a tab to
    see the large-content viewer.
11. ☐ Offer a service: the skills field, Add skill, chips ("selected" state read), radius,
    hours and the save button are reachable in order; errors are announced.
12. ☐ Ask "Track my ex girlfriend's phone": the refusal message is read.

**Evidence:** save the recording and a short note of findings to
`evidence/P2/a11y/<date>/voiceover-walkthrough.mov` and `voiceover-notes.md`. Any item that fails
is a bug to fix before G2.
