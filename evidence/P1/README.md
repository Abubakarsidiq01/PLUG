# Evidence — Phase 1, identity and consent

Nothing here yet. This file exists so the gap is visible rather than discovered at
the gate, and so nobody reads an empty folder as "no evidence was required".

Gate G1 needs all of the following, and the reviewer checks this folder against the
state matrix in manual.docx §12 before anything else.

| Folder | What goes in it | Accepted only if |
|---|---|---|
| `ios/` | One screenshot per required state on the welcome, sign-in and code-entry screens: loading, empty, error, offline, permission denied, expired, partial, success | Captured on a real iPhone, at default **and** at the largest Dynamic Type size |
| `failures/` | At least one deliberate failure and its recovery | Recorded, not described — a wrong code, then the right one, or the tunnel dropped mid-sign-in |
| `a11y/` | A VoiceOver walkthrough of Apple sign-in end to end | Every control is reachable and announced; 44pt minimum targets hold |
| `logs/` | The backend log covering the connected checkpoint | Contains the request ID that also appears in the iOS log, and contains no token, code, phone number or authorization header |

Beyond the folders, the gate also needs:

- Sign in with Apple completed on a physical device, the app force-quit, relaunched,
  and the session still there. This is the sentence the phase is judged on and no
  automated test can stand in for it.
- The correlation ID from the connected checkpoint, quoted in
  `docs/CHECKPOINT_TRACKER.md`.
- Both signatures on the `G1` entry in `PROJECT_STATE.json`.

The automated suites are not evidence for this gate. They are in the repository and
they run in CI; the gate asks what two people saw against real staging.
