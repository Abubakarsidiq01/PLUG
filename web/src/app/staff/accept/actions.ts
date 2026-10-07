"use server";

import { redirect } from "next/navigation";
import { callApi } from "@/lib/staff-api";

export type AcceptState = { error: string | null };

const messages: Record<string, string> = {
  expired: "That invitation does not work any more. Ask an owner to invite you again.",
  length: "Use a password of 12 to 64 characters.",
  too_weak: "That password is too easy to guess. Choose a longer or more unusual one.",
};

// Chooses a password with an emailed invitation (ADR-013). The API decides whether the
// invitation and the password are acceptable; this only passes them on.
export async function acceptInvite(_previous: AcceptState, formData: FormData): Promise<AcceptState> {
  const inviteToken = String(formData.get("invite_token") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  if (!/^sti_[A-Za-z0-9_-]{1,124}$/.test(inviteToken)) return { error: "Paste the invitation code from your email. It starts with sti_." };
  if (password !== String(formData.get("password_repeat") ?? "")) return { error: "The two passwords are different." };
  if (password.length < 12 || password.length > 64) return { error: messages.length };
  const result = await callApi<null>("/v1/staff/invites/accept", {
    method: "POST",
    body: { invite_token: inviteToken, password },
  });
  if (!result.ok) {
    const detail = result.status === 400 ? result.error?.details?.[0]?.code : undefined;
    return { error: (detail && messages[detail]) || "The PLUG server did not answer. Try again." };
  }
  redirect("/admin/login?accepted=1");
}
