import { cookies } from "next/headers";
import { connection } from "next/server";
import { CHALLENGE_COOKIE, apiOrigin } from "@/lib/staff-console";
import { startLogin, verifyLogin } from "./actions";

// Staff sign-in (ADR-013, contract 0.6.0): email and password, then a six-digit code sent
// by email. The page collects credentials only when the server has PLUG_API_URL; without
// it the console stays closed and says so.
const messages: Record<string, string> = {
  check: "Enter your email and password.",
  code: "That code is not right. Check the email and try again.",
  expired: "That sign-in ran out. Start again.",
  limited: "Too many attempts. Wait 15 minutes, then try again.",
  unavailable: "Staff sign-in is not available right now, because the server cannot send email.",
  server: "The PLUG server did not answer. Try again.",
};

function Closed() {
  return (
    <main className="notice-page">
      <div className="container">
        <div className="card notice-card">
          <p className="overline">Admin</p>
          <h1 className="title1">Admin access is not available yet</h1>
          <p>
            This console is reserved for authorized PLUG staff. Admin sign-in will
            require server verification and multi-factor authentication before access
            is enabled. Guest and member accounts cannot open the console.
          </p>
        </div>
      </div>
    </main>
  );
}

export default async function AdminLogin({ searchParams }: PageProps<"/admin/login">) {
  // Read the setting per request, never at build time.
  await connection();
  if (apiOrigin() === null) return <Closed />;

  const { step, error, ref, accepted, signed_out: signedOut } = await searchParams;
  const codeStep = step === "code" && (await cookies()).has(CHALLENGE_COOKIE);
  const message = typeof error === "string" ? messages[error] : undefined;
  const supportReference = typeof ref === "string" && /^req_[A-Za-z0-9-]{1,80}$/.test(ref) ? ref : null;

  return (
    <main className="notice-page">
      <div className="container">
        <div className="card notice-card">
          <p className="overline">Admin</p>
          <h1 className="title1">{codeStep ? "Enter your code" : "Staff sign in"}</h1>
          {accepted === "1" && !message ? <p role="status">Your staff account is ready. Sign in below.</p> : null}
          {signedOut === "1" && !message ? <p role="status">You are signed out.</p> : null}
          {message ? (
            <p className="form-error" role="alert">
              {message}
              {supportReference ? <> Reference: <code>{supportReference}</code></> : null}
            </p>
          ) : null}
          {codeStep ? (
            <>
              <p>If the email and password were right, a six-digit code is on its way to your inbox. It works for 10 minutes.</p>
              <form action={verifyLogin} className="form-stack">
                <label className="field">
                  <span className="field-label">Six-digit code</span>
                  <input className="field-input" name="code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9 ]{6,7}" maxLength={7} required />
                </label>
                <button type="submit" className="button button-primary">Sign in</button>
              </form>
              <p><a className="text-link" href="/admin/login">Start again</a></p>
            </>
          ) : (
            <>
              <p>For PLUG staff only. Guest and member accounts cannot open the console.</p>
              <form action={startLogin} className="form-stack">
                <label className="field">
                  <span className="field-label">Email</span>
                  <input className="field-input" type="email" name="email" autoComplete="username" maxLength={254} required />
                </label>
                <label className="field">
                  <span className="field-label">Password</span>
                  <input className="field-input" type="password" name="password" autoComplete="current-password" maxLength={256} required />
                </label>
                <button type="submit" className="button button-primary">Continue</button>
              </form>
            </>
          )}
        </div>
      </div>
    </main>
  );
}
