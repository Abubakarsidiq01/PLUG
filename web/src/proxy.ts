import { NextRequest, NextResponse } from "next/server";

// Phase 0 has no session issuer or verifier. Fail closed until Phase 1 adds
// server-side session verification; an arbitrary browser cookie proves nothing.
// Future admin data/actions must also authorize access at their own boundary.

export function proxy(request: NextRequest) {
  if (request.nextUrl.pathname === "/admin/login") {
    return NextResponse.next();
  }
  const loginUrl = new URL("/admin/login", request.url);
  loginUrl.searchParams.set("from", request.nextUrl.pathname);
  const response = NextResponse.redirect(loginUrl);
  response.headers.set("Cache-Control", "no-store");
  return response;
}

export const config = {
  matcher: ["/admin/:path*"],
};
