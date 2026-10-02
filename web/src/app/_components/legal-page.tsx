import Link from "next/link";
import type { ReactNode } from "react";
import { LegalCopy, sectionId, type LegalSection } from "./legal-copy";

// Shared shell for the private-test legal drafts and support copy: a page head,
// an on-this-page index on wide screens, and the text at a readable measure.
export function LegalPage({
  title,
  lede,
  sections,
  action,
  children,
}: {
  title: string;
  lede: string;
  sections: LegalSection[];
  action?: ReactNode;
  children?: ReactNode;
}) {
  return (
    <main className="legal">
      <header className="page-head">
        <div className="container">
          <p className="overline">Private-test draft</p>
          <h1 className="title1">{title}</h1>
          <p className="page-lede">{lede}</p>
          {action ? <div className="page-action">{action}</div> : null}
        </div>
      </header>
      <div className="container legal-grid">
        <nav aria-label="On this page" className="legal-index">
          <p className="overline">On this page</p>
          <ul>
            {sections.map((section) => (
              <li key={section.heading}>
                <a href={`#${sectionId(section.heading)}`}>{section.heading}</a>
              </li>
            ))}
          </ul>
        </nav>
        <article className="legal-copy">
          {children}
          <LegalCopy sections={sections} />
          <p className="legal-back">
            <Link href="/" className="button button-secondary">Back to home</Link>
          </p>
        </article>
      </div>
    </main>
  );
}
