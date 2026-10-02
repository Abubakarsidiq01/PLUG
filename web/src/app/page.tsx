import type { Metadata } from "next";
import Link from "next/link";
import { CONTACT_EMAIL, JOIN_HREF, JOIN_LABEL } from "./_components/site-chrome";
import { TruthBadge, type TruthLabel } from "./_components/truth-badge";

// manual.docx §15 and Figure 14, updated for ADR-009 (any lawful local service).
// Every sentence here must be true of the private test today: no metrics,
// testimonials, logos, counters, ratings or stock imagery (§15.1, §16.4).
export const metadata: Metadata = {
  title: { absolute: "PLUG — find a local service that fits your budget and time" },
  description:
    "Tell PLUG what you need in plain words. It works out the service, budget and time and shows who nearby can help. In private testing on iPhone.",
};

const steps = [
  {
    title: "You ask",
    body: "Say it in plain words, like “fix the heel on my boots for $45 tomorrow”, or tap a suggestion. A shoe repair, a plumber or a haircut all work.",
  },
  {
    title: "PLUG reads it",
    body: "It pulls out the service, your budget, the time and where to look. If something is unclear, it asks one question with answers you can tap.",
  },
  {
    title: "You see who can help",
    body: "Participating suppliers answer with a price and a time. If none cover your service, you see nearby businesses from Apple Maps, with price and availability marked Unknown.",
  },
];

const truthRows: { label: TruthLabel; meaning: string }[] = [
  { label: "confirmed", meaning: "A supplier or scout verified this within the freshness window." },
  { label: "recent", meaning: "Verified 2 to 10 minutes ago. Still reliable." },
  { label: "estimated", meaning: "Based on patterns or older evidence. Approximate." },
  { label: "unknown", meaning: "No usable evidence, so PLUG says so instead of guessing." },
];

const example = [
  { key: "Service", value: "Shoe repair" },
  { key: "Budget", value: "Up to $45" },
  { key: "When", value: "Tomorrow" },
  { key: "Where", value: "Near you" },
];

export default function Home() {
  return (
    <main className="home">
      <section className="hero" aria-labelledby="home-title">
        <div className="container hero-grid">
          <div className="hero-copy">
            <h1 id="home-title" className="display">
              Find a local service that fits your budget and your time.
            </h1>
            <p className="lede">
              Tell PLUG what you need in plain words. It works out the service, your budget and
              when you need it, then shows who nearby can help. A price or an opening appears
              only when a business actually gave it.
            </p>
            <div className="hero-action">
              <Link href={JOIN_HREF} className="button button-primary">{JOIN_LABEL}</Link>
              <p className="hero-facts">Invite-only · iPhone · United States · free while testing</p>
            </div>
          </div>

          <figure className="card example-card">
            <figcaption className="overline">Example: what PLUG reads from one sentence</figcaption>
            <p className="example-quote">“Fix the heel on my boots for $45 tomorrow”</p>
            <dl className="kv">
              {example.map((row) => (
                <div key={row.key} className="kv-row">
                  <dt>{row.key}</dt>
                  <dd>{row.value}</dd>
                </div>
              ))}
            </dl>
          </figure>
        </div>
      </section>

      <section id="how-it-works" className="band band-muted" aria-labelledby="how-title">
        <div className="container">
          <p className="overline">How it works</p>
          <h2 id="how-title" className="title2">What happens when you ask</h2>
          <ol className="steps">
            {steps.map((step, index) => (
              <li key={step.title}>
                <h3 className="title3">
                  <span>{index + 1}</span>
                  <span aria-hidden="true"> · </span>
                  {step.title}
                </h3>
                <p>{step.body}</p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section id="truth-labels" className="band" aria-labelledby="truth-title">
        <div className="container split">
          <div className="split-intro">
            <p className="overline">Truth labels</p>
            <h2 id="truth-title" className="title2">Every result says how PLUG knows it</h2>
            <p>
              Each result carries one label, set by the PLUG server from the evidence it has.
              The app shows that label as sent. It never upgrades a label as time passes and
              never hides Unknown to make a list look fuller.
            </p>
          </div>
          <div className="card table-card">
          <table className="truth-table">
            <caption className="visually-hidden">What each truth label means</caption>
            <thead>
              <tr>
                <th scope="col">Label</th>
                <th scope="col">Means exactly</th>
              </tr>
            </thead>
            <tbody>
              {truthRows.map((row) => (
                <tr key={row.label}>
                  <th scope="row"><TruthBadge label={row.label} /></th>
                  <td>{row.meaning}</td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        </div>
      </section>

      <section id="status" className="band band-ruled" aria-labelledby="status-title">
        <div className="container split">
          <div className="split-intro">
            <p className="overline">Where things stand</p>
            <h2 id="status-title" className="title2">What the private test does today</h2>
            <ul className="plain-list">
              <li>PLUG is in private testing with invited people on iPhone.</li>
              <li>
                Participating suppliers are demo data in a test zone in Ruston, Louisiana.
                They are not real businesses.
              </li>
              <li>
                When no participating supplier covers your service, the app lists real nearby
                businesses from Apple Maps. PLUG has not heard from them, so their price and
                availability show as Unknown.
              </li>
              <li>Nobody is contacted and nothing is booked yet.</li>
            </ul>
            <p className="aside-note">
              Run a local business? Supplier sign-up is not open yet. You can ask about it
              at <a href={`mailto:${CONTACT_EMAIL}`} className="text-link">{CONTACT_EMAIL}</a>.
            </p>
          </div>
          <aside className="card rules-card" aria-labelledby="rules-title">
            <h3 id="rules-title" className="overline">What PLUG does not do</h3>
            <ul className="square-list">
              <li>Show a price a business did not give us.</li>
              <li>Invent wait times or availability.</li>
              <li>Contact businesses that have not agreed to hear from PLUG.</li>
              <li>Sell your personal information.</li>
            </ul>
          </aside>
        </div>
      </section>
    </main>
  );
}
