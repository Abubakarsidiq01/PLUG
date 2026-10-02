// manual.docx §11.2: the only place truth colours may appear. In the product the
// label is decoded from a server response and never computed by a client; on the
// public site it is only shown as a specimen next to its definition.
export type TruthLabel = "confirmed" | "recent" | "estimated" | "unknown";

const names: Record<TruthLabel, string> = {
  confirmed: "Confirmed",
  recent: "Recent",
  estimated: "Estimated",
  unknown: "Unknown",
};

export function TruthBadge({ label }: { label: TruthLabel }) {
  return <span className={`truth-badge truth-${label}`}>{names[label]}</span>;
}
