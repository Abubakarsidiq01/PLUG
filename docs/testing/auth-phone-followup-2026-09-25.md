# Physical phone follow-up — September 25

## Google request failure

The later phone request IDs were traced to the backend's JSON parser: Google's
1,180-character token exceeded a global 1,000-character string limit. The auth
contract already permits 4,096 characters. The parser now matches that limit;
request text retains its separate 1,000-character validation.

Google regression fixtures now include realistic additional claims. All nine
Google scenarios reproduced the parser failure before the fix and passed after it.
Full backend check and databaseTest: 86 tests, zero failures, against the disposable
validation database. iOS unit/integration suite: 40 tests, zero failures.

## Interface and connectivity

The auth screen uses a plain background, compact wordmark, a bounded form width,
consistent buttons and fixed top alignment. Google uses the correct signup/signin
label and its bundled logo. Unconfigured Apple/SMS methods remain hidden.
Terms, Privacy and Help open bundled, scrollable documents with a Done action,
without depending on a web server. Legal documents explicitly describe private
testing; they are not approved public launch policies.

Reference: [Linear login methods](https://linear.app/docs/login-methods) and
[Notion login flows](https://www.notion.com/help/log-in-and-out). The interactive
browser was unavailable; public references were used.

The previous quick tunnel had stopped resolving. A replacement tunnel and the
fixed backend were started. Public health probes returned 200 in 0.10–0.41 seconds.
A synthetic 1,180-character invalid Google token now reaches authentication and
returns 401 instead of failing JSON parsing. This does not prove real Google login.

The updated signed Debug app was installed on the connected iPhone. The current
API origin is embedded for home-screen launches, and the Xcode scheme matches.
Use tools/set-phone-api.py when the quick tunnel changes, then rebuild.

A real Google sign-in completed successfully on the live backend at 09:42:30 CDT
(POST /v1/auth/google, HTTP 201). The preceding synthetic probes returned 401
as expected. Apple requires an eligible signing setup. Real SMS is not enabled; the free local code-file path
is documented in docs/runbooks/auth-provider-setup.md and is not SMS delivery.

Five simulator UI scenarios passed, covering default/largest text, guest access,
provider selection and all three document links. Screenshot review prompted an
additional accessibility adjustment: the legal footer scrolls with content at
accessibility text sizes instead of consuming most of the viewport.

The two affected UI scenarios passed again after the final accessibility change.
SwiftLint (no cache), whitespace checks and the final signed device build passed.
Final build installed and launched at 09:44 CDT. Screenshots: evidence/P1/simulator/2026-09-25/auth-final.
