# Blueprint auth follow-up — September 25

User supplied IMG_4247–4249: retained as PNG evidence under
`evidence/P1/phone/2026-09-25`, with source and conversion hashes. IMG_4247 confirms
a Google account on the physical iPhone. The welcome photos show the previous UI.

The first branded proposal was subsequently rejected by the user. It is not the
accepted design. After inspecting the manual's embedded Figures 7, 8 and 10, the
implementation was corrected to the illustrated centred logo/wordmark,
streetscape, Get started and I have an account arrangement. The conversation
illustration and generic headline were removed. See design/brand/README.md.

Account logic and provider credentials were not changed. The existing Google and
guest routes remain connected. Legal/help notices still open locally. Apple and
real SMS remain unavailable pending their provider configuration.

Validation: six UI scenarios passed, covering the default/largest text sizes,
guest session and upgrade, provider availability and wording, legal/help sheets,
clickable logo and landscape navigation. The two method-selection/recovery
scenarios passed again after the final context-specific sign-in/signup links.
SwiftLint, whitespace checks and the signed iPhone build passed. Screenshots are
in evidence/P1/simulator/2026-09-25/blueprint-auth; these supersede branded-auth.
The 40 iOS unit/integration tests passed earlier in this work; account logic was
not changed by the subsequent visual revision.

To view welcome on a phone with a restored account, use Profile → Sign out.
Installation preserves the stored account; a signed-in launch correctly opens
the product instead of replaying onboarding. Visual acceptance remains with the
user, and this record is not a G1 sign-off.
