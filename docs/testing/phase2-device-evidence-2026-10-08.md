# Phase 2 device evidence, 8 October 2026

The full state walkthrough on the paired iPhone 13 Pro Max (iOS 26.7.1), at default and
largest Dynamic Type, with the PLUG logotype and the 7 October fixes. Replaces the 4 October
captures for G2.

| | |
|---|---|
| Runner | `tools/run-phase2-device-evidence.sh` (synthetic fixture server over the private paired interface) |
| Result | 7 of 7 walkthroughs passed |
| Captures | 57 in `evidence/P2/ios/2026-10-08/`, greyscale copies in `greyscale/` |
| Do Not Disturb | On. Every capture was checked for a notification band; none has one |

## What the device run found and fixed

- **Back swipe ignored on iOS 26.7.** The test's synthesized edge swipe was sometimes ignored
  on the phone, leaving the test on the request screen (three walkthroughs failed on the first
  run; the recordings show the app behaving correctly). The test now checks that the screen
  went back, retries once, and otherwise taps the visible back button.
- **Cards narrower than the page at the largest sizes.** The "Know before you go" and "Offer a
  service" cards stacked at accessibility sizes but hugged their text instead of filling the
  width. They fill it again; visible in `device-p2-visual-examples-largest.png`.

## Not covered here

The VoiceOver walkthrough is a formal G2 exception (`phase2-g2-exceptions.md`).
