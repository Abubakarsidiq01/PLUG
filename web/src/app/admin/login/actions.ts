"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import type { components } from "@/generated/api";
import { callApi, cookieBase, reference, storeSession, type Session } from "@/lib/staff-api";
import { CHALLENGE_COOKIE } from "@/lib/staff-console";

type Challenge = components["schemas"]["StaffLoginChallenge"];

const login = "/admin/login";

function failure(status: number): string {
  if (status === 429) return "limited";
  if (status === 503) return "unavailable";
  return status === 400 ? "check" : "server";
}

// Step one: email and password. The API answers the same way whether or not they are
// right, so this never tells the caller which it was.
export async function startLogin(formData: FormData): Promise<never> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  if (!email || !password || email.length > 254 || password.length > 256) redirect(`${login}?error=check`);
  const result = await callApi<Challenge>("/v1/staff/login", { method: "POST", body: { email, password } });
  if (!result.ok) redirect(`${login}?error=${failure(result.status)}${reference(result.error)}`);
  const jar = await cookies();
  jar.set(CHALLENGE_COOKIE, result.data.challenge_id, {
    ...(await cookieBase(login)),
    expires: new Date(result.data.expires_at),
  });
  redirect(`${login}?step=code`);
}

// Step two: the emailed code buys the staff session.
export async function verifyLogin(formData: FormData): Promise<never> {
  const jar = await cookies();
  const challenge = jar.get(CHALLENGE_COOKIE)?.value;
  if (!challenge) redirect(`${login}?error=expired`);
  const code = String(formData.get("code") ?? "").replace(/\s/g, "");
  if (!/^[0-9]{6}$/.test(code)) redirect(`${login}?step=code&error=code`);
  const result = await callApi<Session>("/v1/staff/login/verify", {
    method: "POST",
    body: { challenge_id: challenge, code },
  });
  if (!result.ok) {
    const wrongCode = result.status === 400 && result.error?.details?.[0]?.code === "invalid";
    if (wrongCode) redirect(`${login}?step=code&error=code`);
    if (result.status === 400 || result.status === 429) {
      jar.delete({ name: CHALLENGE_COOKIE, path: login });
      redirect(`${login}?error=${result.status === 429 ? "limited" : "expired"}`);
    }
    redirect(`${login}?step=code&error=server${reference(result.error)}`);
  }
  jar.delete({ name: CHALLENGE_COOKIE, path: login });
  // Only a staff session opens the console, whatever else the API might issue.
  if (result.data.account.type !== "staff") redirect(`${login}?error=server`);
  await storeSession(result.data);
  redirect("/admin");
}
