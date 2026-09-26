import Link from "next/link";
import type { ReactNode } from "react";

// Shared shell for the public legal/support routes (docs/design/figma-implementation-checklist.md,
// "Public website"). The final legal text is not approved yet, so each route states
// that plainly instead of inventing terms, contacts or commitments
// (docs/CONTRIBUTOR_WORKFLOW.md rule 4). The site-wide footer in layout.tsx carries the
// links between these pages; this shell only adds the way back home.
export function LegalPage({ title, lede, children }: { title: string; lede: string; children: ReactNode }) {
  return (
    <main className="public-shell">
      <p className="eyebrow">PLUG · Private development</p>
      <h1>{title}</h1>
      <p className="lede">{lede}</p>
      <p>{children}</p>
      <p className="legal-status">Status: placeholder. Final wording is pending approval.</p>
      <nav aria-label="Back" className="legal-back">
        <Link href="/">Back to home</Link>
      </nav>
    </main>
  );
}
