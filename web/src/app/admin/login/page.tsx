// Real sign-in is a Phase 1 task, built against the approved backend session
// design (manual.docx §27.2, P1-TWO.md) — no frontend-only authorization.
// This page exists only so Phase 0 can prove middleware redirects here.
export default function AdminLogin() {
  return (
    <main className="public-shell">
      <p className="eyebrow">PLUG Admin</p>
      <h1>Sign-in not implemented yet</h1>
      <p className="lede">
        Admin sign-in ships in Phase 1, against the backend session design.
      </p>
    </main>
  );
}
