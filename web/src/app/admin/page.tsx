import type { Metadata } from "next";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { AdminInspector, type InspectorData, type InspectorPaging } from "../_components/admin-inspector";
import { callApi, type ApiResult } from "@/lib/staff-api";
import { ACCESS_COOKIE, REFRESH_COOKIE, apiOrigin } from "@/lib/staff-console";
import { signOut } from "./actions";

// The staff console (manual v4 P2-TWO.S12). Closed unless the server has PLUG_API_URL.
// The cookie only carries the token: the API decides on every read whether this is a
// staff session that finished its second factor, and this page shows what it answers.
export const metadata: Metadata = { title: "Classifier inspector" };

const pages = ["gaps", "classifications", "refusals"] as const;
type PageName = (typeof pages)[number];

const loginUrl = "/admin/login?from=%2Fadmin";

function cursorFrom(value: string | string[] | undefined): string | null {
  return typeof value === "string" && /^[A-Za-z0-9_-]{1,512}$/.test(value) ? value : null;
}

function withCursor(path: string, cursor: string | null): string {
  return cursor === null ? path : `${path}?cursor=${cursor}`;
}

export default async function AdminHome({ searchParams }: PageProps<"/admin">) {
  // Decide per request. Without this the build would freeze the page as "closed".
  await connection();
  if (apiOrigin() === null) redirect(loginUrl);
  const jar = await cookies();
  const params = await searchParams;
  const refreshed = params.r === "1";
  const refreshUrl = jar.has(REFRESH_COOKIE) && !refreshed ? "/admin/session/refresh" : loginUrl;
  const token = jar.get(ACCESS_COOKIE)?.value;
  if (!token) redirect(refreshUrl);

  const cursors: Record<PageName, string | null> = {
    gaps: cursorFrom(params.gaps),
    classifications: cursorFrom(params.classifications),
    refusals: cursorFrom(params.refusals),
  };
  const [skills, gaps, classifications, refusals] = await Promise.all([
    callApi<InspectorData["skills"]>("/v1/admin/skills", { token }),
    callApi<InspectorData["gaps"]>(withCursor("/v1/admin/skills/gaps", cursors.gaps), { token }),
    callApi<InspectorData["classifications"]>(withCursor("/v1/admin/classifications", cursors.classifications), { token }),
    callApi<InspectorData["refusals"]>(withCursor("/v1/admin/refusals", cursors.refusals), { token }),
  ]);

  const actions = (
    <form action={signOut}>
      <button type="submit" className="button button-secondary">Sign out</button>
    </form>
  );
  const results: ApiResult<unknown>[] = [skills, gaps, classifications, refusals];
  if (results.some((result) => result.status === 401)) redirect(refreshUrl);
  const failed = results.find((result) => !result.ok);
  if (failed && !failed.ok) {
    const requestId = failed.error?.request_id;
    // One refused or failed read shows no data at all, never a partly filled page.
    return <AdminInspector view={{ kind: failed.status === 403 ? "denied" : "unavailable", requestId }} actions={actions} />;
  }
  if (!skills.ok || !gaps.ok || !classifications.ok || !refusals.ok) redirect(loginUrl);

  const data: InspectorData = { skills: skills.data, gaps: gaps.data, classifications: classifications.data, refusals: refusals.data };
  // Each table pages on its own; a link keeps the other tables where they are.
  const paging: InspectorPaging = {};
  for (const name of pages) {
    const link = (cursor: string | null) => {
      const query = new URLSearchParams();
      for (const other of pages) {
        const value = other === name ? cursor : cursors[other];
        if (value !== null) query.set(other, value);
      }
      const text = query.toString();
      return text ? `/admin?${text}` : "/admin";
    };
    const next = data[name].next_cursor;
    paging[name] = { next: next === null ? null : link(next), first: cursors[name] === null ? null : link(null) };
  }
  return <AdminInspector view={{ kind: "ready", data, source: "live", paging }} actions={actions} />;
}
