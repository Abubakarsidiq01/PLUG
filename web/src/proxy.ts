import { NextRequest, NextResponse } from "next/server";
import { ACCESS_COOKIE, REFRESH_COOKIE, apiOrigin } from "@/lib/staff-console";

// The staff console fails closed. Without PLUG_API_URL nothing under /admin opens except
// the notice on /admin/login. With it, only the console page and its session refresh are
// let through, and only for a browser that holds a staff cookie. That cookie proves
// nothing here: the API checks the token, the admin scope and the second factor on every
// read (ADR-013), and the page shows only what the API returns.
const consolePaths = ["/admin", "/admin/session/refresh"];

export function proxy(request: NextRequest) {
  const path = request.nextUrl.pathname;
  if (path === "/admin/login") {
    return NextResponse.next();
  }
  const holdsSession = request.cookies.has(ACCESS_COOKIE) || request.cookies.has(REFRESH_COOKIE);
  if (apiOrigin() !== null && consolePaths.includes(path) && holdsSession) {
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
