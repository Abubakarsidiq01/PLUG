import Link from "next/link";
import type { ReactNode } from "react";
import { Brand } from "./brand-art";

// Shared shell for the public legal/support routes (docs/design/figma-implementation-checklist.md,
// "Public website"). The final legal text is not approved yet, so each route's own copy
// says so instead of inventing terms, contacts or commitments
// (docs/CONTRIBUTOR_WORKFLOW.md rule 4). The site-wide footer in layout.tsx carries the
// links between these pages; this shell only adds the way back home.
export function LegalPage({ title, lede, children }: { title: string; lede: string; children: ReactNode }) {
  return (
    <main className="public-shell">
      <Brand />
      <article className="card">
        <p className="eyebrow">Private development</p>
        <h1>{title}</h1>
        <p className="lede">{lede}</p>
        <p>{children}</p>
      </article>
      <nav aria-label="Back" className="legal-back">
        <Link href="/">
          <span aria-hidden="true">←</span> Back to home
        </Link>
      </nav>
    </main>
  );
}
