# P3.S16 and P3.S7 iOS evidence

Synthetic fixture-server screenshots (ios/PlugUITests/Support/request_fixture_server.py), not live
backend or device evidence. Captured by PlugUITests/RequestScreenshotTests on an iPhone 17 Pro
simulator (iOS 26.5). `-default` is the default text size; `-largest` is Accessibility XXXL.

| File | State |
| --- | --- |
| `accessibility-audit-inbox-item-open.txt` | Apple accessibility audit findings for this Inbox screen (testInboxAccessibilityAudit). inbox-item-open has one open finding: contrast on the system date picker's time button. |
| `accessibility-audit-inbox-list.txt` | Apple accessibility audit findings for this Inbox screen (testInboxAccessibilityAudit). inbox-item-open has one open finding: contrast on the system date picker's time button. |
| `booking-canceled-default.png` | The asker canceled while the reservation was pending. |
| `booking-canceled-largest.png` | The asker canceled while the reservation was pending. |
| `booking-confirmed-default.png` | Asker confirmed booking (only after the server says confirmed). |
| `booking-confirmed-largest.png` | Asker confirmed booking (only after the server says confirmed). |
| `booking-not-confirmed-default.png` | Not confirmed: the time to confirm ran out and no other offer was left. |
| `booking-not-confirmed-largest.png` | Not confirmed: the time to confirm ran out and no other offer was left. |
| `booking-pending-cancel-default.png` | Asker pending reservation: waiting for the provider, booking reference, confirm-by time. (asker flow: cancel) |
| `booking-pending-cancel-largest.png` | Asker pending reservation: waiting for the provider, booking reference, confirm-by time. (asker flow: cancel) |
| `booking-pending-confirm-default.png` | Asker pending reservation: waiting for the provider, booking reference, confirm-by time. (asker flow: confirm) |
| `booking-pending-confirm-largest.png` | Asker pending reservation: waiting for the provider, booking reference, confirm-by time. (asker flow: confirm) |
| `booking-pending-release-default.png` | Asker pending reservation: waiting for the provider, booking reference, confirm-by time. (asker flow: release) |
| `booking-pending-release-largest.png` | Asker pending reservation: waiting for the provider, booking reference, confirm-by time. (asker flow: release) |
| `booking-pending-timeout-default.png` | Asker pending reservation: waiting for the provider, booking reference, confirm-by time. (asker flow: timeout) |
| `booking-pending-timeout-largest.png` | Asker pending reservation: waiting for the provider, booking reference, confirm-by time. (asker flow: timeout) |
| `booking-recovery-default.png` | Alternate-offer recovery after the provider released: the remaining offer. |
| `booking-recovery-largest.png` | Alternate-offer recovery after the provider released: the remaining offer. |
| `inbox-chosen-actions-default.png` | Chosen, scrolled to Confirm and Can't make it. |
| `inbox-chosen-actions-largest.png` | Chosen, scrolled to Confirm and Can't make it. |
| `inbox-chosen-default.png` | Chosen: the asker picked this offer; booking reference and confirm-by countdown. |
| `inbox-chosen-largest.png` | Chosen: the asker picked this offer; booking reference and confirm-by countdown. |
| `inbox-closed-default.png` | Closed: the asker canceled, nothing booked. |
| `inbox-closed-largest.png` | Closed: the asker canceled, nothing booked. |
| `inbox-composer-error-default.png` | Composer with the inline over-budget error. |
| `inbox-composer-error-largest.png` | Composer with the inline over-budget error. |
| `inbox-confirmed-default.png` | Confirmed by the provider: Booked with the reference. |
| `inbox-confirmed-largest.png` | Confirmed by the provider: Booked with the reference. |
| `inbox-decline-dialog-default.png` | Decline dialog with the five optional MatchDecline reasons. |
| `inbox-decline-dialog-largest.png` | Decline dialog with the five optional MatchDecline reasons. |
| `inbox-declined-default.png` | Declined state after choosing a reason. |
| `inbox-declined-largest.png` | Declined state after choosing a reason. |
| `inbox-empty-default.png` | Inbox with no matched requests yet (provider_inbox on, empty list). |
| `inbox-error-default.png` | Inbox load failed (500): error notice with Try again. |
| `inbox-error-largest.png` | Inbox load failed (500): error notice with Try again. |
| `inbox-list-default.png` | Inbox list: Needs your answer (New, Chosen) and Earlier, with countdowns and the hourly cap. |
| `inbox-list-largest.png` | Inbox list: Needs your answer (New, Chosen) and Earlier, with countdowns and the hourly cap. |
| `inbox-list-more-default.png` | Inbox list scrolled: Earlier items (Declined, Missed, Not chosen, Closed). |
| `inbox-list-more-largest.png` | Inbox list scrolled: Earlier items (Declined, Missed, Not chosen, Closed). |
| `inbox-loading-default.png` | Inbox while the first load is in flight. |
| `inbox-loading-largest.png` | Inbox while the first load is in flight. |
| `inbox-missed-default.png` | Missed: the reply window passed (MatchStatus expired). |
| `inbox-missed-largest.png` | Missed: the reply window passed (MatchStatus expired). |
| `inbox-not-chosen-default.png` | Not chosen: the provider released it, nothing booked. |
| `inbox-not-chosen-largest.png` | Not chosen: the provider released it, nothing booked. |
| `inbox-offer-sent-default.png` | Offer sent: price, start, offer end and note. |
| `inbox-offer-sent-largest.png` | Offer sent: price, start, offer end and note. |
| `inbox-open-default.png` | An open request: what they need, the offer composer and Decline. |
| `inbox-open-largest.png` | An open request: what they need, the offer composer and Decline. |
| `inbox-rate-limited-default.png` | Inbox load answered 429: plain wait-and-retry message. |
| `inbox-rate-limited-largest.png` | Inbox load answered 429: plain wait-and-retry message. |
| `offer-choose-cancel-largest.png` | Asker Offer Detail scrolled to Choose this offer. (asker flow: cancel) |
| `offer-choose-confirm-largest.png` | Asker Offer Detail scrolled to Choose this offer. (asker flow: confirm) |
| `offer-choose-release-largest.png` | Asker Offer Detail scrolled to Choose this offer. (asker flow: release) |
| `offer-choose-timeout-largest.png` | Asker Offer Detail scrolled to Choose this offer. (asker flow: timeout) |
| `offer-detail-cancel-default.png` | Asker Offer Detail with Choose this offer (an SMS offer, so no note). (asker flow: cancel) |
| `offer-detail-cancel-largest.png` | Asker Offer Detail with Choose this offer (an SMS offer, so no note). (asker flow: cancel) |
| `offer-detail-confirm-default.png` | Asker Offer Detail with Choose this offer; the in-app offer shows its note. (asker flow: confirm) |
| `offer-detail-confirm-largest.png` | Asker Offer Detail with Choose this offer; the in-app offer shows its note. (asker flow: confirm) |
| `offer-detail-release-default.png` | Asker Offer Detail with Choose this offer (an SMS offer, so no note). (asker flow: release) |
| `offer-detail-release-largest.png` | Asker Offer Detail with Choose this offer (an SMS offer, so no note). (asker flow: release) |
| `offer-detail-timeout-default.png` | Asker Offer Detail with Choose this offer (an SMS offer, so no note). (asker flow: timeout) |
| `offer-detail-timeout-largest.png` | Asker Offer Detail with Choose this offer (an SMS offer, so no note). (asker flow: timeout) |

Not captured: the inbox 404 (provider_inbox off) state, which has its own copy but no fixture route; inbox-empty at the largest text size (the default-text walk only); the 401 signed-out state.
