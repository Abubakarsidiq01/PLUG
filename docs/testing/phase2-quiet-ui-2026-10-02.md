# Phase 2 UI refinement after the custom-skills update

Owner requested a less crowded, more natural interface after Claude's updates. The starting point is `e67abf9`, including ADR-011's 115-tag vocabulary and provider-described skills. This iteration changes native presentation only; the business-profile API, optional photo/link storage, matching, and custom-skill behavior are preserved.

- Ask home concentrates on the active ask while it is open. The composer and examples return after it stops. Open and Stop are direct, comfortably tappable text actions, with a vertical arrangement at accessibility sizes.
- Secondary actions use simple text and native navigation indicators. Examples and external business links use plain rows, without repeated outlined button surfaces.
- Offer summaries keep business identity, price, truth label, time, distance, and expiry. The longer business introduction appears on the detail page, where offer facts precede optional external links.
- Provider setup keeps optional public business details in an expandable row. Opening or closing it preserves drafts. The expanded form still supports a photo, description, and five links; existing custom skills and licensed-skill rules are unchanged.
- The existing paper/ink palette, evidence colors, type scaling, and 44-point touch targets remain in use.

Verification evidence: `evidence/P2/simulator/2026-10-02/quiet-ui/`. The UI walkthrough checks both default and largest text sizes, optional-section expansion/collapse, custom-skill selection, offers, and home cancellation. Screenshots use clearly synthetic fixtures, not real supplier endorsements.

Reverting this visual experiment requires restoring only the presentation changes in `AskView.swift` and `ProviderView.swift` to `e67abf9`, plus the matching UI-test changes. Copies of those baseline views are also in ignored `output/ui-refinement-after-claude/`. Do not revert the earlier business-profile or custom-skills commits, the owner's `gradlew.bat` changes, or delete stored business profiles.

G2 remains unsigned; this visual review does not replace the outstanding phase checkpoint.

## Visual Ask home, October 3

The Ask home now uses one un-nested composer, a compact send control, and two visual example actions: a monochrome barber still life and the existing neighborhood illustration. Additional examples are collapsed. The headline and helper copy are shorter, while actual result truth labels and demo-offer disclosures remain intact. This supersedes the earlier text-only home decluttering pass.

`AskBarber.imageset/barber.png` was generated with the imagegen skill as editorial example imagery. It does not depict or endorse a registered provider. It appears only in example discovery, never as a provider profile photo. The original is preserved under the local generated-images directory; the app consumes its bundled asset copy.

The visual-home UI test verifies both example tiles fill the correct text without submitting, at normal and largest Dynamic Type. Evidence: `evidence/P2/simulator/2026-10-03/visual-home/`. The preceding full walkthrough passed four UI tests and produced 48 screenshots under `quiet-ui/`.

Final visual-home checks: example selection and service-offer/home-cancellation tests passed at both text sizes (two XCTest methods, 12 screenshots). Signed physical-iPhone build passed. Installation of this latest visual-home build was unsuccessful because the paired device connection reset; the previously installed quiet-UI build is an earlier revision. The existing API is healthy on localhost:18080, but its HTTPS hostname no longer resolves. Automatic approval review rejected opening a replacement public tunnel; explicit owner approval was requested and no replacement tunnel was opened.

Phone follow-up (October 3): the visual-home build was successfully installed and launched on the paired physical iPhone. The owner authorized proceeding with phone testing; automatic approval review still rejected the replacement public tunnel because backend payload safety was not established. No replacement tunnel was opened, and live API connectivity on this run is unverified.

Connection repair (October 3): Cloudflare confirmed the old preview tunnel no longer exists. A safer private relay, bound exclusively to the CoreDevice paired-interface IPv6 address and restricted to the paired phone, now forwards to the existing authenticated localhost backend. No public tunnel or Wi-Fi listener was opened. Installed and launched the Debug build with this address and a local-network usage description. Observed real phone responses: POST /v1/auth/refresh 200; GET /v1/me 200; GET /v1/providers/me 404 (no provider profile). Runtime script and status-only log: `/tmp/plug-paired-relay.py`, `/tmp/plug-paired-relay.log`. This private connection requires the devices to remain paired/connected; addresses may change on reconnection.
