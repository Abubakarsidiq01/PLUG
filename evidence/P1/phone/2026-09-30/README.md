# Physical-phone acceptance and Person One sign-off

Date: 2026-09-30. Signer: Abubakar Bolakale (Person One), by explicit confirmation
in the project conversation. The owner reports that the tested phone flows work,
including VoiceOver, and requests sign-off and progression toward Phase 2.

## Accepted device scope

- Google and guest flow: owner accepted; screenshots 4321/4322 show both profiles.
- Connectivity: 4317 and 4323 show success; all three distinct request IDs match
  backend GET /health HTTP 200 lines in backend-correlation.txt.
- Enlarged text: 4318 demonstrates the Engineering screen at an accessibility
  text size. The exact OS slider setting and all other screens are not established
  by this image alone. Owner reports the requested phone testing passed.
- Offline/retry recovery: 4319 shows the offline state; 4320 shows restored
  connectivity, consistent with the owner's successful recovery report.
- VoiceOver: explicitly confirmed passed by the owner. Static images cannot
  independently demonstrate spoken labels or focus traversal.

All seven supplied images were visually reviewed. No account email, notification
content, credential or OTP was visible. PNGs are format conversions only, with
source and artifact hashes in provenance.json. Existing September 29 Google
persistence/logout acceptance remains recorded; this does not invent a new test.

## Sign-off boundary

Person One's acceptance of the available physical-phone flow is signed off.
This is not an unconditional G1 pass and is not Person Two's signature.

Apple device sign-in remains untested because the owner cannot currently fund
eligible membership. Real SMS remains disabled and budget-deferred under ADR-007.
Final legal publication and its implementation gaps remain recorded in the privacy
review. The joint staging-profile abuse checkpoint and Person Two's acceptance
are not evidenced by these screenshots. A guest-to-new-account identity-preserving
upgrade is not established merely by showing guest and Google profiles.

PR #30 at 6e6de5f had all eight reported checks successful when this evidence was
recorded. It still needs review and is behind main; green CI does not merge it or
sign the project gate. Phase 2 was requested by the owner; full G1 remains open
unless its outstanding requirements are completed or explicitly amended.
