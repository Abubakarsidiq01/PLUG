// ADR-006 issues guest/member sessions only. Admin enrollment and MFA arrive
// in Phase 5; this shell must not collect credentials before that flow exists.
export default function AdminLogin() {
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
