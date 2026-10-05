# Direct skill entry — 2026-10-03

Owner request: typing a service such as “Wig install” must not depend on automatic suggestions.

The provider form now has a direct **Add skill** action. Suggestions remain optional, and
failure leaves the text available for direct entry. One entry field replaces the duplicate
custom-skill field. Labels use the existing 3–40 character and five-entry limits.
On save, listed names resolve to canonical skills; new names retain own-words matching.
Licensed services still require a licence, and a licence-required response reveals the
licence field in the app. Existing restricted-intent checks remain active.

Validation:
- 63 backend unit tests, 8 contract tests and 8 focused PostGIS provider/ask tests passed.
- The focused database test uses isolated `plug_skills_fix_1003b`, never the phone database.
- A local HTTP save on port 18085 returned canonical `wig_install` plus custom `Kiln glazing`;
  the synthetic profile has `accepting=false`.
- Simulator direct-entry/save tests cover normal and largest text, including a failed
  suggestion request. Screenshots: `evidence/P2/simulator/2026-10-03/direct-skills/`.
- Signed physical-device build installed and launched. The real phone refreshed its session
  and loaded its account successfully through the private relay.

Development connection:
- The paired CoreDevice address changed when its connection ended. A devicectl notification
  observation now holds the paired connection open for four hours; it logs no app content.
- Current private relay: `[fd64:4a1e:3bad::2]:18086` → `127.0.0.1:18085`, accepting only
  the paired phone (`::1`) and Mac (`::2`). No public tunnel was created.
- Runtime scripts/logs are under `/tmp/plug-paired-*`; backend log is
  `/tmp/plug-skills-backend.log`. Existing phone database and user account were preserved.
- If the phone disconnects or the held connection expires, the paired address may change;
  the development URL will need updating again. This is a temporary local testing setup.

No G2 approval or contract sign-off is implied. Existing unrelated UI work remains intact.
