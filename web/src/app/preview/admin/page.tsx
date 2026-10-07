import { readFile } from "node:fs/promises";
import path from "node:path";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { connection } from "next/server";
import { AdminInspector, type InspectorData, type InspectorView } from "../../_components/admin-inspector";

// A local preview of the staff inspector, drawn from the synthetic fixtures in
// /fixtures/admin.*. It exists so the page can be built and reviewed before staff
// sign-in does. It is not the admin console: it calls no API, holds no session and
// answers 404 unless PLUG_ADMIN_PREVIEW=fixtures is set on the server. /admin itself
// stays closed in src/proxy.ts.
export const metadata: Metadata = {
  title: "Admin preview",
  robots: { index: false, follow: false },
};

async function fixture<T>(operation: string, outcome: string): Promise<T> {
  const file = path.join(process.cwd(), "..", "fixtures", `admin.${operation}`, `${outcome}.json`);
  return JSON.parse(await readFile(file, "utf8")) as T;
}

type ErrorBody = { error: { request_id: string } };

async function sample(): Promise<InspectorData> {
  const [skills, gaps, classifications, refusals] = await Promise.all([
    fixture<InspectorData["skills"]>("skills", "success"),
    fixture<InspectorData["gaps"]>("gaps", "success"),
    fixture<InspectorData["classifications"]>("classifications", "success"),
    fixture<InspectorData["refusals"]>("refusals", "success"),
  ]);
  return { skills, gaps, classifications, refusals };
}

const empty: InspectorData = {
  skills: { skills: [], custom_skills: [] },
  gaps: { items: [], next_cursor: null },
  classifications: { items: [], next_cursor: null },
  refusals: { items: [], next_cursor: null },
};

// ?state= picks which designed state to show, so each one can be reviewed and tested.
async function viewFor(state: string | undefined): Promise<InspectorView> {
  switch (state) {
    case "empty":
      return { kind: "ready", data: empty, source: "sample" };
    case "loading":
      return { kind: "loading" };
    case "denied":
      return { kind: "denied", requestId: (await fixture<ErrorBody>("skills", "forbidden")).error.request_id };
    case "unavailable":
      return { kind: "unavailable", requestId: (await fixture<ErrorBody>("skills", "transient-error")).error.request_id };
    default:
      return { kind: "ready", data: await sample(), source: "sample" };
  }
}

export default async function AdminPreview({ searchParams }: PageProps<"/preview/admin">) {
  // Read the switch per request, never at build time, so a production build cannot bake it in.
  await connection();
  if (process.env.PLUG_ADMIN_PREVIEW !== "fixtures") notFound();
  const { state } = await searchParams;
  return <AdminInspector view={await viewFor(typeof state === "string" ? state : undefined)} />;
}
