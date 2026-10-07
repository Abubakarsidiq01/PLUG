import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { callApi, clearSession, storeSession, type Session } from "@/lib/staff-api";
import { REFRESH_COOKIE, apiOrigin } from "@/lib/staff-console";

// The access token lasts 15 minutes; a staff refresh chain lasts at most 12 hours. The
// console page sends the browser here when the API says the access token ran out. Every
// refresh rotates the token, so this happens in one place and never during a page render.
export async function GET(): Promise<never> {
  const refresh = (await cookies()).get(REFRESH_COOKIE)?.value;
  if (apiOrigin() === null || !refresh) redirect("/admin/login?from=%2Fadmin");
  const result = await callApi<Session>("/v1/auth/refresh", { method: "POST", body: { refresh_token: refresh } });
  if (!result.ok || result.data.account.type !== "staff") {
    await clearSession();
    redirect("/admin/login?error=expired");
  }
  await storeSession(result.data);
  // r=1 tells the page this session was just refreshed, so a second refusal ends at sign-in.
  redirect("/admin?r=1");
}
