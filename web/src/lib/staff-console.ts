// Where the staff console finds the PLUG API, and the names of its cookies. Shared by
// src/proxy.ts and the server code under src/app/admin, so it imports nothing from Next.

export const ACCESS_COOKIE = "plug_staff_access";
export const REFRESH_COOKIE = "plug_staff_refresh";
export const CHALLENGE_COOKIE = "plug_staff_challenge";

const loopbackHosts = ["127.0.0.1", "localhost", "[::1]"];

export function isLoopback(hostname: string): boolean {
  return loopbackHosts.includes(hostname);
}

// The console is closed unless the server is given PLUG_API_URL. Anything other than
// HTTPS, or plain HTTP to this machine, is treated as not configured: staff passwords
// and tokens are never sent over an open connection.
export function apiOrigin(): URL | null {
  const value = process.env.PLUG_API_URL;
  if (!value) return null;
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  if (url.protocol === "https:") return url;
  return url.protocol === "http:" && isLoopback(url.hostname) ? url : null;
}
