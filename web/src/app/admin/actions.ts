"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { callApi, clearSession } from "@/lib/staff-api";
import { ACCESS_COOKIE } from "@/lib/staff-console";

// Revokes the session on the server first, which is what makes "signed out" true, then
// drops the cookies whatever the server said.
export async function signOut(): Promise<never> {
  const token = (await cookies()).get(ACCESS_COOKIE)?.value;
  if (token) await callApi<null>("/v1/auth/logout", { method: "POST", token });
  await clearSession();
  redirect("/admin/login?signed_out=1");
}
