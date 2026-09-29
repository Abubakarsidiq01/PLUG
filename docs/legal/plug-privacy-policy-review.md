# PLUG Privacy Policy - review draft

## Privacy policy

### Review status

Revised September 28, 2026. This is a review draft for the current private-testing service, not an effective public-launch policy. The retention schedule, teen safeguards and deletion procedures require the work listed in the implementation appendix. The existing app consent version has not been changed.

### 1. Who is responsible

PLUG is operated by Abubakar Bolakale in the United States. For privacy questions or requests, contact privacy@plugapp.com. The owner confirmed this operator name, operating country and contact address for this revision.

### 2. What this policy covers

This policy describes personal information processed through PLUG’s current iOS app, test API, website and support interactions. Current testing focuses on Google and guest authentication, account sessions and consent records. Apple and phone authentication are implemented but require provider setup before they are available in a particular build.

### Features that are not yet live

Booking, supplier outreach, NOW/Live Checks, Scout contributions, photos, credits, push notifications and AI request processing are planned features. Their presence in a roadmap or navigation tab does not mean that they are operating. We will describe their actual collection, recipients, retention and choices before enabling them. This policy does not claim that their safeguards already exist.

### Our current approach

PLUG does not sell personal information or share it for cross-context behavioral advertising in the current test service. We do not operate advertising tracking or a background location-history feature. Guest access still creates an identifier and server records; it is not anonymous. Hashed identifiers remain personal information when they can be linked to an account.

### Other services

Google, Apple and other independent services have their own privacy notices. This policy describes PLUG’s practices; it does not replace the notices for services you choose to use.

## Information we handle

### 3. Accounts and authentication

When you use Google or Apple sign-in, your selected provider returns an authentication credential that may contain identity claims. PLUG verifies the credential and uses the verified provider identifier to recognize your account. The current account database stores a keyed hash of that identifier, an internal user ID, provider type, account status and timestamps; it does not maintain name or email profile fields. Receiving claims during authentication is distinct from storing them in a profile. PLUG does not receive your Google or Apple password.

### Phone authentication

If phone sign-in is enabled, PLUG receives the number you enter, sends a one-time code through the configured delivery provider and processes the code you submit. Account matching uses a keyed phone-number hash. The raw destination number and SMS contents must be provided to the SMS provider to deliver the message; hashing our account identifier does not hide those details from that provider. Currently real SMS delivery is not configured.

### Sessions and notice records

We process access and refresh credentials, session and account IDs, issue/expiry/revocation times, the notice version acknowledged and its timestamp. The iPhone stores app session credentials in Keychain. The backend stores hashes of PLUG session credentials rather than the reusable credentials themselves. A notice acknowledgement records what was shown; it is not blanket consent to every form of processing.

### Requests, support and diagnostics

If a tester sends information to the request API, it receives the submitted text and coordinates, which can be precise. The current endpoint validates and acknowledges that input; it does not complete a booking or send it to suppliers. Support information comes from what you send us. Connection providers receive technical information such as IP addresses, request metadata and timing. PLUG records request IDs, outcomes and security/audit events; some anti-abuse checks use network-address prefixes.

### Information outside the current scope

The implemented test features do not request payment-card details, contacts, health records, camera/photo uploads, background location, advertising identifiers or push tokens. Do not send unnecessary sensitive information, passwords, sign-in codes or another person’s private information in a request or support message.

## Purposes and recipients

### 4. Why we process information

We use account and session information to authenticate you, maintain access and revoke sessions. We use challenge, replay and rate-limit records to prevent misuse. We use notice records to demonstrate the version acknowledged, and operational records to investigate failures, support users and protect the service. Information may also be needed to meet a specific legal obligation or establish, exercise or defend a legal claim. We do not claim a legal obligation where none applies.

### 5. Who may receive it

Access by the project team should be limited to what is needed for operation, support and security. Google processes Google sign-in; Apple processes Apple sign-in when enabled. Public test traffic currently passes through Cloudflare tunnels to team-controlled development infrastructure, so Cloudflare handles traffic needed to provide that service. Twilio is the configured SMS integration but is not currently delivering messages. Its processing applies when that channel is enabled. Support messages are also processed by the service used to operate our support inbox.

### Limits on provider statements

The present test deployment is not an AWS-hosted production service. No AI model, maps, analytics or crash-reporting vendor is identified as an active data recipient by this review. We will verify contracts, service settings, data categories and processing locations before adding a provider. We do not promise a particular vendor protection, training restriction or deletion schedule without verifying it.

### Other disclosures

We may disclose relevant information when legally required, to investigate fraud or protect rights and safety, or at your direction. We assess requests and limit disclosure to what is appropriate. If an organizational transfer affects personal information, we will provide any required notice and apply applicable safeguards; a transaction does not permit unlimited new uses. We will not describe linked or merely hashed records as anonymous.

### Regional legal bases

Where EEA/UK data-protection law applies, necessary account-service processing may rely on performance of a contract; proportionate security and service administration may rely on legitimate interests; optional processing may require consent; and specified legal obligations may require retention or disclosure. Each purpose must have a valid basis. Withdrawal of consent does not make earlier lawful processing unlawful. The owner must confirm regional availability and the applicable bases before public launch.

## Retention and security

### 6. Retention criteria

Account, session, notice and security records are currently retained in the test database unless deliberately removed through an authorized process. No automatic database-record deletion or backup-expiry schedule has been established by this review. We need to set and enforce a documented retention schedule before public launch. Criteria include whether an account or investigation is active, the purpose of a record, the sensitivity of the data, applicable legal duties and the availability of less identifying records.

### Credential expiry is not record deletion

Current PLUG access credentials last 15 minutes. Rotating refresh credentials last 30 days for a verified account or 7 days for a guest. Phone codes expire after 10 minutes when the channel is enabled. Expired or revoked credentials should no longer grant access, but their database records may remain. These validity periods are not promises that associated personal information has been deleted.

### Deletion, exceptions and backups

A deletion request requires a verified, documented process covering active records, linked identifiers and any backups or exports. Security/audit records need a defined lawful purpose and limited retention; the present audit store is append-only and needs an appropriate retention mechanism. If information must be retained, access should be restricted and the reason explained where permitted. Removing the app or signing out does not itself delete server-side records.

### 7. Security measures

The current implementation uses HTTPS for public test connections, Keychain for iPhone credentials, hashed server-side session credentials, keyed identity hashes, access checks, rotating refresh sessions, replay controls, rate limits and audit records. Logging is designed to exclude passwords, session credentials and one-time codes. No security measure guarantees absolute protection. Private development infrastructure should not be described as having verified AWS KMS encryption, production staff MFA or production backup controls.

### Incidents and safe contact

If a security incident affects personal information, we will assess its impact and make notifications required by applicable law. Contact privacy@plugapp.com with concerns. Do not include passwords or OTPs. State what happened, when, the app version and a request ID if available.

## Your choices and rights

### 8. Requests and identity checks

Contact privacy@plugapp.com to ask about your information, request access or correction, or request deletion. Describe the request and how you use PLUG, without sending credentials. We may request proportionate information to verify that the account or data is yours, and use it for that verification. An authorized agent may act where applicable law permits, subject to appropriate authority and identity checks. If a request cannot be fulfilled in full, we will explain the reason and available review route as required by law.

### Available rights depend on applicable law

Depending on your location and which laws apply to PLUG, rights may include access, correction, deletion, portability, objection, restriction, withdrawal of consent, or an appeal. Relevant laws may also provide rights relating to targeted advertising, sale/sharing and sensitive information. The current service does not sell personal information or use cross-context behavioral advertising. We will respond within applicable legal time limits and explain any permitted extension. You may complain to an appropriate regulator. We will not unlawfully discriminate against you for exercising rights.

### Current deletion limitation

The current private-test app has no Delete Account screen or completed automated account-deletion flow. Contacting us initiates a request; it does not instantly delete records. Stopping Google/Apple authorization, logging out or removing the app is not the same as deleting PLUG data. An in-app account-deletion pathway and any required provider-token revocation must be implemented and verified before an App Store release with account creation.

### 9. Permissions, age and international processing

The current test features do not request the planned location, camera, photos or notification permissions. Before those features launch, PLUG must explain why a permission is requested and the available alternative. PLUG is intended for people aged 15 or older. Users aged 15 to 17 need permission from a parent or legal guardian. We do not knowingly collect information from children under 15; contact us if you believe this has occurred so we can investigate and arrange appropriate removal. The current test app has no implemented age-assurance or parental-permission process; do not admit minors until these safeguards are in place. PLUG is operated in the United States. Providers may process information elsewhere; actual locations and any legally required transfer safeguards must be confirmed before offering the service in additional regions.

### 10. Changes

We will date revisions and give appropriate notice of material changes, with consent where required. A revised policy does not automatically authorize incompatible uses of previously collected data. Keep the policy, in-app notice, backend version and any App Store disclosures consistent. Contact: privacy@plugapp.com.

## Implementation appendix

### Confirmed for this revision

The owner confirmed Abubakar Bolakale as operator, United States operations, privacy@plugapp.com as the controlled contact address, and a minimum age of 15 with appropriate safeguards. Verify that the mailbox actually receives and handles requests before displaying it to users. The September 26 source policy has been rewritten around the verified Phase 1 implementation, rather than assuming the whole product blueprint is live.

### Decisions still required

Implement the approved 15+ rule and proportionate age/parental-permission safeguards; define actual retention periods and a deletion/backup schedule; decide supported regions and any required representatives/transfer mechanisms; document support-mail hosting and any additional recipients. These are operational decisions, not blanks that can safely be filled with arbitrary legal-sounding numbers.

### Safeguards for ages 15 to 17

Before enrolling minors, establish a proportionate age check and parental-permission process, a parent/guardian request route, understandable notices and protective defaults. Do not expose a teen’s identity or precise location to strangers; do not enable advertising profiling or optional sharing by default. Collect only age information actually needed rather than routinely asking for identity documents. Assess location, supplier contact, photo contributions and Scout participation separately before enabling them for teens. The legal standard for children and parental consent varies by region; parental permission alone does not resolve every requirement.

### Engineering work before publication

Implement and test account deletion, identity verification for privacy requests and any necessary Apple token revocation. Establish a lawful cleanup process for append-only audit records. Add expiry/deletion jobs and prove them against tests. Verify actual hosting security and backup behavior. Maintain a provider inventory and data-flow record. Publish matching web/iOS text only after these facts are settled; then update the consent version in one reviewed change.

## Launch review

### Before enabling later features

Bookings and suppliers: disclose actual request/contact sharing and SMS preferences. Scouts and photos: confirm visibility, metadata removal, abuse controls and retention. Location: specify purpose, precision, duration and manual alternative. AI: identify the provider, fields sent, retention and training settings; do not promise non-training without a verified basis. Analytics and notifications: identify actual SDKs/recipients and user choices. Update disclosures before collection begins.

### What this review does not certify

This document is a strengthened review draft, not a legal compliance certification or approval to release. It does not establish that account deletion, retention jobs, age controls or cross-border safeguards are already implemented. G1 remains open for the separately recorded device/staging requirements. Obtain jurisdiction-appropriate legal review before public launch.

### Primary guidance used

FTC: Consumer Privacy - ftc.gov/business-guidance/privacy-security/consumer-privacy. ICO: Right to be informed - ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/individual-rights/individual-rights/right-to-be-informed/. Apple: Offering account deletion in your app - developer.apple.com/support/offering-account-deletion-in-your-app. Checked September 28, 2026. These sources inform the review; their applicability depends on the service and jurisdiction.
