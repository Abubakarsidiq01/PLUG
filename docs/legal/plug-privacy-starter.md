# Privacy Policy - private-test starter draft

Prepared September 30, 2026. Not a public-launch agreement; existing consent version unchanged.

Generated from `web/src/content/legal-starter.json`; edit that shared source and regenerate this review copy.

## 1. Operator and current scope

Abubakar Bolakale operates PLUG in the United States. Contact privacy@plugapp.com. This September 30, 2026 draft describes the private test, not all roadmap features. Google and guest access are available. Apple sign-in and real SMS delivery are deferred. Booking, supplier outreach, payments, photos, push notifications and AI fulfillment are not yet live.

## 2. Information processed

PLUG processes provider authentication credentials and identity claims, a keyed hash of the verified provider identifier, internal user identifiers, account status, session records, consent versions and timestamps. The current account database has no name or email profile fields; transient authentication claims can contain information not stored in that profile. Guest identifiers and hashed identifiers can still be personal information. PLUG does not receive your Google password. App session credentials are stored in the iPhone Keychain; the server stores hashes of PLUG session credentials.

## 3. Requests and technical records

The test request API can receive submitted text and coordinates, including precise coordinates; it validates and acknowledges requests without arranging a booking. Support receives information you choose to send. Request IDs, outcomes, security events and some network-address prefixes support troubleshooting and abuse prevention. Connection providers process technical metadata, including IP addresses. Do not submit unnecessary sensitive information, another person’s private information, passwords or one-time codes.

## 4. Purposes and recipients

Information is used to authenticate accounts, maintain and revoke sessions, record notice acknowledgments, prevent misuse, diagnose problems and answer support or privacy requests. Information may also be used for an applicable legal obligation or a legitimate legal claim. Google processes Google sign-in. Cloudflare carries public test traffic to team-controlled development infrastructure. Authorized team members and the inbox provider may process information needed for operation or support. Apple and Twilio would process authentication or delivery data only when their integrations are enabled. We do not sell personal information or use it for cross-context behavioral advertising in the current test; no production AWS, AI, analytics or maps processing is claimed.

## 5. Retention and deletion

Test database records remain until removed through an authorized process. An automated record-deletion and backup-expiry schedule has not been established. Access credentials expire after 15 minutes; refresh credentials expire after 30 days for a verified account or 7 days for a guest. Credential expiry does not erase database records. Internal account deletion revokes sessions and marks an account deleted, but is not complete personal-data erasure. Audit records are append-only. Retention limits and a verified deletion/backup process must be implemented before public launch; no arbitrary deletion deadline is promised here.

## 6. Requests, rights and security

Contact privacy@plugapp.com to request access, correction or deletion, or raise a concern. We may need proportionate verification of your identity and any agent’s authority, without collecting passwords or OTPs. Rights and response deadlines depend on applicable law; requests, refusals and any permitted extensions must be handled accordingly. You may contact the relevant regulator, and exercising legal rights must not lead to unlawful discrimination. Signing out, removing the app or withdrawing provider authorization does not itself erase PLUG records. HTTPS, Keychain, hashed credentials, access controls, rotation, replay protection and rate limits reduce risk but cannot guarantee absolute security. Incidents must be assessed and notified as required by law.

## 7. Age, location and changes

PLUG’s intended minimum age is 15, with parent or guardian permission for ages 15 to 17. Age and parental-permission safeguards are not implemented, so minors must not be enrolled in this test until those safeguards are ready. Notify us if a child under 15 has supplied information so it can be investigated and handled appropriately. The operator is in the United States; provider processing locations and any required international-transfer measures must be confirmed before offering the service in additional regions. Material changes will be dated and communicated with any legally required choice or consent. Future features require updated disclosures before their data collection begins.
