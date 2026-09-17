import { NextRequest, NextResponse } from "next/server";

// Phase 0 placeholder: no real session exists until Phase 1 (identity and
// consent) ships. This enforces the shape of the rule now — every /admin
// route requires a session cookie, unauthenticated requests are redirected,
// never rendered — so Phase 1 only has to swap the cookie check for real
// session verification, never invent the redirect behaviour from scratch.
// No frontend-only authorization: the backend must independently enforce
// the same rule once admin API routes exist (docs/AI_START_HERE.md rule 6).
const SESSION_COOKIE = "plug_admin_session";

export function proxy(request: NextRequest) {
  if (request.nextUrl.pathname.startsWith("/admin/login")) {
    return NextResponse.next();
  }
  const session = request.cookies.get(SESSION_COOKIE);
  if (!session) {
    const loginUrl = new URL("/admin/login", request.url);
    loginUrl.searchParams.set("from", request.nextUrl.pathname);
    return NextResponse.redirect(loginUrl);
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/admin/:path*"],
};
