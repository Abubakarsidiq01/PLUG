import Link from "next/link";
import type { ReactNode } from "react";
import { Brand } from "./brand-art";

// Shared brand shell for the private-test legal drafts and support copy.
// The content source and review status are shared across the three routes.
export function LegalPage({ title, lede, children }: { title: string; lede: string; children: ReactNode }) {
  return (
    <main className="public-shell">
      <Brand />
      <article className="card">
        <p className="eyebrow">Private development</p>
        <h1>{title}</h1>
        <p className="lede">{lede}</p>
        <div className="legal-copy">{children}</div>
      </article>
      <nav aria-label="Back" className="legal-back">
        <Link href="/">
          <span aria-hidden="true">←</span> Back to home
        </Link>
      </nav>
    </main>
  );
}
