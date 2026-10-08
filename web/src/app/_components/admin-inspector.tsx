import type { ReactNode } from "react";
import type { components } from "@/generated/api";

// Manual v4 P2-TWO.S12: the staff view of the skill vocabulary and the classifier's
// recent decisions. Every shape here comes from the generated contract types, so a
// state added to the contract fails the build instead of rendering an empty cell.
// This file only draws data it is handed. It never fetches and never classifies.
// /preview/admin hands it the fixtures; /admin hands it what the API returned.
type Schemas = components["schemas"];
type Classification = Schemas["AdminClassificationPage"]["items"][number];

export type InspectorData = {
  skills: Schemas["AdminSkillVocabulary"];
  gaps: Schemas["AdminVocabularyGapPage"];
  classifications: Schemas["AdminClassificationPage"];
  refusals: Schemas["AdminRefusalPage"];
};

// Links for one paged table: the next page, and the way back once past the first.
type PageLinks = { next: string | null; first: string | null };
export type InspectorPaging = Partial<Record<"gaps" | "classifications" | "refusals", PageLinks>>;

export type InspectorView =
  | { kind: "ready"; data: InspectorData; source: "sample" | "live"; paging?: InspectorPaging }
  | { kind: "loading" }
  | { kind: "denied"; requestId?: string }
  | { kind: "unavailable"; requestId?: string };

const stateNames: Record<Classification["state"], string> = {
  resolved: "Resolved",
  awaiting_clarification: "Awaiting clarification",
  unresolved: "Unresolved",
};

const askTypeNames: Record<NonNullable<Classification["ask_type"]>, string> = {
  service_request: "Service request",
  place_question: "Place question",
};

const timeFormat = new Intl.DateTimeFormat("en-US", {
  dateStyle: "medium",
  timeStyle: "short",
  timeZone: "UTC",
});

function Time({ value }: { value: string }) {
  return <time dateTime={value}>{timeFormat.format(new Date(value))} UTC</time>;
}

function Section({ id, title, note, children }: { id: string; title: string; note: string; children: ReactNode }) {
  return (
    <section className="inspector-section" aria-labelledby={id}>
      <h2 id={id} className="title2">{title}</h2>
      <p className="inspector-note">{note}</p>
      {children}
    </section>
  );
}

function DataTable({ label, columns, empty, children }: { label: string; columns: string[]; empty: string; children: ReactNode[] }) {
  if (children.length === 0) return <p className="card inspector-empty">{empty}</p>;
  return (
    <div className="card table-card inspector-scroll" role="region" aria-label={`${label} table`} tabIndex={0}>
      <table className="truth-table inspector-table">
        <thead>
          <tr>{columns.map((column) => <th key={column} scope="col">{column}</th>)}</tr>
        </thead>
        <tbody>{children}</tbody>
      </table>
    </div>
  );
}

// next_cursor means the server has more rows. Paging needs a live session, so the
// sample view states that more exist instead of offering a link that goes nowhere.
function More({ cursor, links }: { cursor: string | null; links?: PageLinks }) {
  if (!links) return cursor === null ? null : <p className="inspector-more">More entries exist beyond this page.</p>;
  if (links.next === null && links.first === null) return null;
  return (
    <p className="inspector-more inspector-pager">
      {links.first === null ? null : <a className="text-link" href={links.first}>Back to the newest</a>}
      {links.next === null ? null : <a className="text-link" href={links.next}>Older entries</a>}
    </p>
  );
}

function Notice({ title, body, requestId }: { title: string; body: string; requestId?: string }) {
  return (
    <div className="card notice-card">
      <h2 className="title2">{title}</h2>
      <p>{body}</p>
      {requestId ? <p className="inspector-reference">Reference: <code>{requestId}</code></p> : null}
    </div>
  );
}

function Ready({ data, paging }: { data: InspectorData; paging?: InspectorPaging }) {
  return (
    <>
      <Section
        id="inspector-skills"
        title="Skill vocabulary"
        note="The listed skills an ask or a provider can be matched on, with how many providers hold each one."
      >
        <DataTable label="Skill vocabulary" columns={["Skill", "Tag", "Group", "Licence", "Providers"]} empty="No skills are listed.">
          {data.skills.skills.map((skill) => (
            <tr key={skill.tag}>
              <td>{skill.display}</td>
              <td><code>{skill.tag}</code></td>
              <td>{skill.parent}</td>
              <td>{skill.requires_licence ? "Required" : "Not required"}</td>
              <td>{skill.provider_count}</td>
            </tr>
          ))}
        </DataTable>
        <h3 className="title3 inspector-subhead">Skills in providers&rsquo; own words</h3>
        <DataTable label="Skills in providers' own words" columns={["Label", "Tag", "Providers"]} empty="No provider has added a skill in their own words.">
          {data.skills.custom_skills.map((skill) => (
            <tr key={skill.tag}>
              <td>{skill.label}</td>
              <td><code>{skill.tag}</code></td>
              <td>{skill.provider_count}</td>
            </tr>
          ))}
        </DataTable>
      </Section>

      <Section
        id="inspector-gaps"
        title="Vocabulary gaps"
        note="Words people used that matched no listed skill. Terms are user content, so each one stays hidden until you open it."
      >
        <DataTable label="Vocabulary gaps" columns={["Term", "Times seen", "First seen", "Last seen"]} empty="No unmatched terms have been recorded.">
          {data.gaps.items.map((gap, index) => (
            <tr key={`${gap.first_seen}-${index}`}>
              <td>
                <details className="inspector-reveal">
                  <summary>Show term</summary>
                  <span>{gap.term}</span>
                </details>
              </td>
              <td>{gap.seen_count}</td>
              <td><Time value={gap.first_seen} /></td>
              <td><Time value={gap.last_seen} /></td>
            </tr>
          ))}
        </DataTable>
        <More cursor={data.gaps.next_cursor} links={paging?.gaps} />
      </Section>

      <Section
        id="inspector-classifications"
        title="Recent classifications"
        note="How each recent ask is classified now. Asks keep no history of reclassification, and no ask text, location or identity is shown."
      >
        <DataTable label="Recent classifications" columns={["Ask", "Created", "Classified as", "State", "Skills"]} empty="No asks have been classified yet.">
          {data.classifications.items.map((item) => (
            <tr key={item.ask_id}>
              <td><code>{item.ask_id}</code></td>
              <td><Time value={item.created_at} /></td>
              <td>{item.ask_type === null ? "Not classified" : askTypeNames[item.ask_type]}</td>
              <td>{stateNames[item.state]}</td>
              <td>
                {item.skill_tags.length === 0
                  ? "None"
                  : item.skill_tags.map((tag) => <code key={tag} className="inspector-tag">{tag}</code>)}
              </td>
            </tr>
          ))}
        </DataTable>
        <More cursor={data.classifications.next_cursor} links={paging?.classifications} />
      </Section>

      <Section
        id="inspector-refusals"
        title="Refusals"
        note="Asks refused by the restricted-intent policy. Only the rule and the time are recorded here."
      >
        <DataTable label="Refusals" columns={["Rule", "When"]} empty="No asks have been refused.">
          {data.refusals.items.map((refusal, index) => (
            <tr key={`${refusal.occurred_at}-${index}`}>
              <td><code>{refusal.rule}</code></td>
              <td><Time value={refusal.occurred_at} /></td>
            </tr>
          ))}
        </DataTable>
        <More cursor={data.refusals.next_cursor} links={paging?.refusals} />
      </Section>
    </>
  );
}

export function AdminInspector({ view, actions }: { view: InspectorView; actions?: ReactNode }) {
  return (
    <main>
      <div className="page-head">
        <div className="container">
          {actions}
          <p className="overline">Admin</p>
          <h1 className="title1">Classifier inspector</h1>
          <p className="page-lede">The skill vocabulary and how recent asks were classified.</p>
          {view.kind === "ready" && view.source === "sample" ? (
            <p className="inspector-sample">Sample data from the repository fixtures. Nothing on this page is live.</p>
          ) : null}
        </div>
      </div>
      <div className="container inspector-body">
        {view.kind === "ready" ? <Ready data={view.data} paging={view.paging} /> : null}
        {view.kind === "loading" ? <p className="card inspector-empty" role="status">Loading the inspector.</p> : null}
        {view.kind === "denied" ? (
          <Notice
            title="You do not have access"
            body="This view is for authorized PLUG staff who signed in with a second factor."
            requestId={view.requestId}
          />
        ) : null}
        {view.kind === "unavailable" ? (
          <Notice
            title="The inspector could not load"
            body="The PLUG server did not answer. Nothing is shown rather than showing old data. Reload the page to try again."
            requestId={view.requestId}
          />
        ) : null}
      </div>
    </main>
  );
}
