"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { callApi, reference } from "@/lib/staff-api";
import { ACCESS_COOKIE } from "@/lib/staff-console";

// Owner actions on the Staff page (ADR-013). The API decides who may do them: a staff member
// who is not an owner is refused there, and this page only reports the answer.
const page = "/admin/staff";

function outcome(status: number, code?: string): string {
  if (status === 401) return "expired";
  if (status === 403) return "owner";
  if (status === 409) return code === "self" ? "self" : "conflict";
  if (status === 400) return "email";
  if (status === 503) return "mail";
  return "server";
}

export async function inviteStaff(formData: FormData): Promise<never> {
  const token = (await cookies()).get(ACCESS_COOKIE)?.value;
  if (!token) redirect(`/admin/login?from=${encodeURIComponent(page)}`);
  const email = String(formData.get("email") ?? "").trim();
  const role = formData.get("role") === "owner" ? "owner" : "staff";
  if (!email || email.length > 254) redirect(`${page}?error=email`);
  const result = await callApi<null>("/v1/admin/staff/invites", { method: "POST", body: { email, role }, token });
  if (!result.ok) redirect(`${page}?error=${outcome(result.status)}${reference(result.error)}`);
  redirect(`${page}?done=invited`);
}

export async function disableStaff(formData: FormData): Promise<never> {
  const token = (await cookies()).get(ACCESS_COOKIE)?.value;
  if (!token) redirect(`/admin/login?from=${encodeURIComponent(page)}`);
  const userId = String(formData.get("user_id") ?? "");
  if (!/^usr_[A-Za-z0-9-]{1,60}$/.test(userId)) redirect(`${page}?error=server`);
  const result = await callApi<null>(`/v1/admin/staff/${userId}/disable`, { method: "POST", token });
  if (!result.ok) {
    const self = result.status === 409 && /own account/i.test(result.error?.message ?? "");
    redirect(`${page}?error=${outcome(result.status, self ? "self" : undefined)}${reference(result.error)}`);
  }
  redirect(`${page}?done=disabled`);
}
