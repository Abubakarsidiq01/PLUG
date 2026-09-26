// ADR-006 issues guest/member sessions only. Admin enrollment and MFA arrive
// in Phase 5; this shell must not collect credentials before that flow exists.
export default function AdminLogin() {
  return (
    <main className="public-shell">
      <p className="eyebrow">PLUG Admin</p>
      <h1>Admin access is not available yet</h1>
      <p className="lede">
        This console is reserved for authorized PLUG staff. Admin sign-in will
        require server verification and multi-factor authentication before access
        is enabled. Guest and member accounts cannot open the console.
      </p>
    </main>
  );
}
