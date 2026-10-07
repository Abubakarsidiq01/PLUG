import { cookies, headers } from "next/headers";
import type { components } from "@/generated/api";
import { ACCESS_COOKIE, REFRESH_COOKIE, apiOrigin, isLoopback } from "./staff-console";

// Server-side calls from the staff console to the PLUG API (ADR-013). The browser never
// sees a token: the session lives in HttpOnly cookies scoped to /admin, and every call is
// made here with the access token as a bearer. The API stays the authorization boundary;
// a cookie only says which token to present.
type Schemas = components["schemas"];
export type Session = Schemas["Session"];
export type ApiError = Schemas["Error"]["error"];

export type ApiResult<T> =
  | { ok: true; status: number; data: T }
  // status 0 means the API was not reached, or answered with something unreadable.
  | { ok: false; status: number; error: ApiError | null };

export async function callApi<T>(
  path: string,
  init: { method?: "GET" | "POST"; body?: unknown; token?: string; forwardedFor?: string | null } = {},
): Promise<ApiResult<T>> {
  const origin = apiOrigin();
  if (origin === null) return { ok: false, status: 0, error: null };
  const requestHeaders: Record<string, string> = { Accept: "application/json" };
  if (init.body !== undefined) requestHeaders["Content-Type"] = "application/json";
  if (init.token) requestHeaders.Authorization = `Bearer ${init.token}`;
  // The API counts sign-in attempts per caller address. It believes this header only from a
  // server listed in its PLUG_TRUSTED_PROXIES, so every staff member gets their own limit.
  if (init.forwardedFor) requestHeaders["X-Forwarded-For"] = init.forwardedFor;
  try {
    const response = await fetch(new URL(path, origin), {
      method: init.method ?? "GET",
      headers: requestHeaders,
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
      cache: "no-store",
      redirect: "error",
      signal: AbortSignal.timeout(10000),
    });
    const text = await response.text();
    const parsed: unknown = text ? JSON.parse(text) : null;
    if (response.ok) return { ok: true, status: response.status, data: parsed as T };
    return { ok: false, status: response.status, error: (parsed as Schemas["Error"] | null)?.error ?? null };
  } catch {
    return { ok: false, status: 0, error: null };
  }
}

// Secure everywhere except a server reached on this machine over plain HTTP. A request a proxy
// marks as HTTPS is always Secure, even when the proxy rewrites the host to localhost.
export async function cookieBase(path: string) {
  const incoming = await headers();
  const hostname = (incoming.get("host") ?? "").replace(/:\d+$/, "");
  const https = incoming.get("x-forwarded-proto")?.split(",")[0]?.trim() === "https";
  return { httpOnly: true, secure: https || !isLoopback(hostname), sameSite: "strict" as const, path };
}

// The browser's address as this site's own ingress reported it, if it did. Only an address is
// passed on; anything else is dropped.
export async function clientAddress(): Promise<string | null> {
  const incoming = await headers();
  const candidate = (incoming.get("x-forwarded-for")?.split(",")[0] ?? incoming.get("x-real-ip") ?? "").trim();
  return /^[0-9A-Fa-f.:]{2,45}$/.test(candidate) ? candidate : null;
}

export async function storeSession(session: Session): Promise<void> {
  const jar = await cookies();
  const base = await cookieBase("/admin");
  jar.set(ACCESS_COOKIE, session.access_token, { ...base, expires: new Date(session.access_token_expires_at) });
  jar.set(REFRESH_COOKIE, session.refresh_token, { ...base, expires: new Date(session.refresh_token_expires_at) });
}

export async function clearSession(): Promise<void> {
  const jar = await cookies();
  jar.delete({ name: ACCESS_COOKIE, path: "/admin" });
  jar.delete({ name: REFRESH_COOKIE, path: "/admin" });
}

// Only the support reference travels in a redirect, and only when it looks like one.
export function reference(error: ApiError | null): string {
  const id = error?.request_id;
  return id && /^req_[A-Za-z0-9-]{1,80}$/.test(id) ? `&ref=${id}` : "";
}
