# G1 Person One sign-off and Phase 2 private-development handoff

Date: 2026-09-30. Approved by Abubakar Bolakale (Person One), through the
explicit instruction to review, sign off and hand both PRs back for manual merge.
Person Two's independent approval is in person-two-checkpoint-2026-09-30.md,
PR #32 head f0e0287. Her signature covers her stated scope, not this addendum.

## Runtime identity and environment

The shared API process is PID 11668, started September 28; its startup log says
Spring profile `db`, and health reports `0.0.1-SNAPSHOT` / `dev`. It is exposed by
a temporary Cloudflare HTTPS tunnel on the owner's Mac. It is not the dedicated
Spring `staging` profile and does not prove production ingress or migration-role
separation. The exact startup commit was not embedded, so no immutable deployment
SHA is claimed. Backend source tree fbb56a2da81de693662dc7e9225f0dd20b5cd6ca
is identical in 7434b13, the reviewed PR #30 source, and PR #32. The last backend
main-source commit is ef760acb4f895cebceed447be8d439266bd94cc7. This is source
provenance corroboration, not a substitute for future immutable deployment metadata.

## Completed checks

- Person Two's own-machine external auth run: 16 requests / 31 assertions passed.
  The server log has a matching 16-request sequence at 19:27:39-44 UTC on the same
  day (her note says approximately 19:29 UTC). Preserved status/path/request-ID
  lines corroborate the sequence; no client request IDs were supplied in her
  original report, so individual client-to-server ID equality is not invented.
- Person One's fresh external rate-limit run: 14 checks passed. Five starts with
  disabled delivery return 503; the sixth returns 429. Five attempts against a
  synthetic unknown challenge return 400; the sixth returns 429. Both limits
  return Retry-After, and health remains 200 afterward. No SMS or tokens issued.
  All 14 response IDs matched backend request logs.
- Previously verified member A/B ownership, identity-preserving upgrade, actual
  incorrect-code attempts, consent and session replay: 35 isolated local live
  assertions passed on September 28. See ../checkpoint/2026-09-28/. Member BOLA
  coverage remains local/disposable, not a claim that it ran through this tunnel.
- 109 backend tests including two-device deletion revocation passed; web build,
  lint and 81 browser tests passed for the starter legal changes.
- Owner accepted Google/guest, enlarged text, offline recovery and VoiceOver.
  Three physical phone IDs match server logs in ../phone/2026-09-30/.
  Those phone images were taken earlier that day, not simultaneously with the
  Windows run. VoiceOver is explicit owner attestation.
- Runtime log scan found no matching Bearer/session-credential-shaped values.
  This is a targeted check, not a guarantee covering every possible secret type.

## Decision and carried limitations

Accept G1 for proceeding to Phase 2 private development under the owner's
explicit budget deferrals and request to sign off. This is a scoped handoff,
not an unconditional original-blueprint pass or public-release approval.

Apple provisioning/device sign-in and real SMS remain deferred under ADR-008.
The external checkpoint demonstrates the identity-enabled db profile through
HTTPS; dedicated staging-profile, immutable build metadata, production ingress
and external member BOLA must be closed before an external beta/public release.
Full screenshot-matrix coverage and real guest-upgrade evidence remain separate
from the accepted owner flow. The tested internal delete revokes access; full
personal-data erasure, retention jobs, teen safeguards and final affirmative
legal consent remain release requirements. Starter legal pages stay labeled drafts.
Do not enroll minors or enable paid/provider features on the strength of this gate.

Both PRs remain for the owner to merge. Phase 2 starts with its jointly reviewed
request/status/location/money contract, preserving the frozen auth model.
