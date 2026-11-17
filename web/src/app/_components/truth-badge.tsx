import type { ReactNode } from "react";
// manual.docx §11.2: the only place truth colours may appear. In the product the
// label is decoded from a server response and never computed by a client; on the
// public site it is only shown as a specimen next to its definition.
export type TruthLabel = "confirmed" | "recent" | "estimated" | "unknown" | "not_verified";

const names: Record<TruthLabel, string> = {
  confirmed: "Confirmed",
  recent: "Recent",
  estimated: "Estimated",
  unknown: "Unknown",
  not_verified: "Not verified",
};

// Icon + word + border, so the state reads without colour (ADR-015). Icons are decorative.
const icons: Record<TruthLabel, ReactNode> = {
  confirmed: <path d="M4 10.5l4 4 8-9" />,
  recent: <><circle cx="10" cy="10" r="7" /><path d="M10 6v4.5l3 1.5" /></>,
  estimated: <path d="M3 8c2-2.5 4-2.5 7 0s5 2.5 7 0M3 14h14" />,
  unknown: <><circle cx="10" cy="10" r="7" strokeDasharray="3 2.5" /><path d="M8 8a2 2 0 1 1 3 1.7c-.7.4-1 .8-1 1.5M10 14v.5" /></>,
  not_verified: <><circle cx="10" cy="10" r="7" /><path d="M3 10h14M10 3c-3 3.5-3 10.5 0 14M10 3c3 3.5 3 10.5 0 14" /></>,
};

export function TruthBadge({ label }: { label: TruthLabel }) {
  return (
    <span className={`truth-badge truth-${label}`}>
      <svg className="truth-icon" viewBox="0 0 20 20" aria-hidden="true" focusable="false">{icons[label]}</svg>
      {names[label]}
    </span>
  );
}
