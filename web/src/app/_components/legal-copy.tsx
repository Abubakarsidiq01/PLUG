type Section = { heading: string; paragraphs: string[] };

export function LegalCopy({ sections }: { sections: Section[] }) {
  return (
    <>
      <p className="legal-draft">For private-test review. Not a public-launch agreement; the existing app consent version has not changed.</p>
      {sections.map((section) => (
        <section key={section.heading}>
          <h2>{section.heading}</h2>
          {section.paragraphs.map((paragraph) => <p key={paragraph}>{paragraph}</p>)}
        </section>
      ))}
      <p><a href="mailto:privacy@plugapp.com">Contact PLUG: privacy@plugapp.com</a></p>
    </>
  );
}
