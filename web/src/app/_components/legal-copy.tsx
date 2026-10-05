import { CONTACT_EMAIL } from "./site-chrome";

export type LegalSection = { heading: string; paragraphs: string[] };

export function sectionId(heading: string) {
  return heading.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

export function LegalCopy({ sections }: { sections: LegalSection[] }) {
  return (
    <>
      <p className="legal-draft">For private-test review. Not a public-launch agreement; the existing app consent version has not changed.</p>
      {sections.map((section) => (
        <section key={section.heading} id={sectionId(section.heading)} aria-labelledby={`${sectionId(section.heading)}-h`}>
          <h2 id={`${sectionId(section.heading)}-h`} className="title3">{section.heading}</h2>
          {section.paragraphs.map((paragraph) => <p key={paragraph}>{paragraph}</p>)}
        </section>
      ))}
      <p className="legal-contact"><a href={`mailto:${CONTACT_EMAIL}`} className="text-link">Contact PLUG: {CONTACT_EMAIL}</a></p>
    </>
  );
}
