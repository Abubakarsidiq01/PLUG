# ADR-008: Defer paid Apple provisioning and real SMS

- Status: Accepted by the project owner on 2026-09-30
- Scope: private development; explicit amendment to the Phase 1 Apple exit criterion

The owner explicitly deferred Apple provisioning and real SMS until a later
stage because funding is unavailable. Phase 1/2 private development uses Google
and guest access. Neither paid integration is required to purchase now. Keep both
provider flags disabled; do not display working Apple/SMS actions or claim they
were tested on a physical device.

Retain server verification, revocation, rate-limit and OTP regression coverage.
Local development OTP is a test aid, never proof of SMS receipt or production
phone-number ownership. Two-way SMS and iMessage remain later integration work.

Revisit funding at Phase 3 planning and before enabling either channel. Before
an external beta/App Store submission, review applicable platform login rules,
complete required Apple configuration, and capture actual device evidence. Before
real SMS, configure an authorized sender, delivery/abuse controls, cost limits and
actual receipt evidence. If funding is still unavailable, keep the feature off
and document the updated release scope; do not silently mark it complete.

This deferral does not waive security checks, legal obligations, truthful privacy
notices, or the joint checkpoint. It does not authorize spending. G1 can be
assessed against this amended scope once remaining evidence is recorded.
