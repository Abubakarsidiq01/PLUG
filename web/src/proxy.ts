import { NextRequest, NextResponse } from "next/server";
import { ACCESS_COOKIE, REFRESH_COOKIE } from "@/lib/staff-console";

// The staff console fails closed. Only the console page and its session refresh are let
// through, and only for a browser that holds a staff cookie. That cookie proves nothing
// here: the API checks the token, the admin scope and the second factor on every read
// (ADR-013), and the page shows only what the API returns.
// PLUG_API_URL is deliberately not read in this file. A proxy's environment is fixed when
// the site is built, so the switch is checked where it is read per request: the page and
// the refresh route send everyone to /admin/login when it is not set.
const consolePaths = ["/admin", "/admin/session/refresh"];

export function proxy(request: NextRequest) {
  const path = request.nextUrl.pathname;
  if (path === "/admin/login") {
    return NextResponse.next();
  }
  const holdsSession = request.cookies.has(ACCESS_COOKIE) || request.cookies.has(REFRESH_COOKIE);
  if (consolePaths.includes(path) && holdsSession) {
    return NextResponse.next();
  }
  const loginUrl = new URL("/admin/login", request.url);
  loginUrl.searchParams.set("from", path);
  const response = NextResponse.redirect(loginUrl);
  response.headers.set("Cache-Control", "no-store");
  return response;
}

export const config = {
  matcher: ["/admin/:path*"],
};
