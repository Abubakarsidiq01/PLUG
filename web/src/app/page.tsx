import type { Metadata } from "next";
import Link from "next/link";
import { CONTACT_EMAIL, JOIN_HREF, JOIN_LABEL } from "./_components/site-chrome";
import { PlugMarkAnimated } from "./_components/brand-art";
import { TruthBadge, type TruthLabel } from "./_components/truth-badge";

// Manual v4 §12A and §15: both ask types, with private-test limitations explicit.
// Every sentence here must be true of the private test today: no metrics,
// testimonials, logos, counters, ratings or stock imagery (§15.1, §16.4).
export const metadata: Metadata = {
  title: { absolute: "PLUG — find a local service that fits your budget and time" },
  description:
    "Tell PLUG what you need in plain words. It works out the service, budget and time and shows who nearby can help. In private testing on iPhone.",
};

// The three steps, tied to the worked example in the hero. The "result" lines say
// only what the private test does today (demo suppliers, no offers when no match).
const steps = [
  {
    title: "You ask",
    body: "Say it in plain words, or tap a suggestion. A shoe repair, a plumber or a haircut all work.",
    result: "“Fix the heel on my boots for $45 tomorrow”",
  },
  {
    title: "PLUG reads it",
    body: "It pulls out the service, your budget, the time and where to look. If something is unclear, it asks one question with answers you can tap.",
    result: "Shoe repair, up to $45, tomorrow, near you",
  },
  {
    title: "You see who can help",
    body: "Service asks are matched to skills, distance and available hours. Place questions have their own answer state. In this private test, offers are synthetic and live place answers are not available yet.",
    result: "Demo offers from the Ruston test zone, or no offers if nothing matches",
  },
];

const truthRows: { label: TruthLabel; meaning: string }[] = [
  { label: "confirmed", meaning: "A supplier or scout verified this within the freshness window." },
  { label: "recent", meaning: "Checked recently. The result shows the age of that evidence." },
  { label: "estimated", meaning: "Based on patterns or older evidence. Approximate." },
  { label: "unknown", meaning: "No usable evidence, so PLUG says so instead of guessing." },
  { label: "not_verified", meaning: "A web source that no person checked. Always dashed, never promoted to human evidence." },
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
            <PlugMarkAnimated className="hero-mark" />
            <h1 id="home-title" className="display">
              Ask for a service. Ask about a place.
            </h1>
            <p className="lede">
              Describe what you need in your own words and PLUG shows who nearby can help.
              Live answers about places are not available in this private test yet, so those
              questions show Unknown.
            </p>
            <div className="hero-action">
              <Link href={JOIN_HREF} className="button button-primary">{JOIN_LABEL}</Link>
              <p className="hero-facts">An invite-only iPhone test in the United States. Free while testing.</p>
            </div>
          </div>

          <figure className="card example-card">
            <figcaption className="example-label">What PLUG reads from one sentence</figcaption>
            <p className="example-quote">“Fix the heel on my boots for $45 tomorrow”</p>
            <dl className="kv">
              {example.map((row) => (
                <div key={row.key} className="kv-row">
                  <dt>{row.key}</dt>
                  <dd>{row.value}</dd>
                </div>
              ))}
            </dl>
            <p className="example-caption">An example of an ask, not a live offer.</p>
          </figure>
        </div>
      </section>

      <section id="how-it-works" className="band band-card" aria-labelledby="how-title">
        <div className="container">
          <h2 id="how-title" className="title2">What happens when you ask</h2>
          <ol className="steps">
            {steps.map((step) => (
              <li key={step.title}>
                <h3 className="title3">{step.title}</h3>
                <div>
                  <p>{step.body}</p>
                  <p className="step-result">{step.result}</p>
                </div>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section id="truth-labels" className="band band-muted" aria-labelledby="truth-title">
        <div className="container split">
          <div className="split-intro">
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

      <section id="status" className="band" aria-labelledby="status-title">
        <div className="container split">
          <div className="split-intro">
            <h2 id="status-title" className="title2">What the private test does today</h2>
            <ul className="plain-list">
              <li>PLUG is in private testing with invited people on iPhone.</li>
              <li>
                Participating suppliers are demo data in a test zone in Ruston, Louisiana.
                They are not real businesses.
              </li>
              <li>
                A service without matching coverage ends with no offers. Place questions
                show Unknown until live answers are available. PLUG does not invent either.
              </li>
              <li>Nobody is contacted and nothing is booked yet.</li>
            </ul>
            <div id="offer" className="offer-section">
              <h3 className="title3">Put your skills on PLUG</h3>
              <p>Invited testers can offer a service from the same account. Describe what
                you do, confirm your skills and choose your travel area and hours.
                Inbox delivery and booking come later.</p>
              <p>Ask about testing at <a href={`mailto:${CONTACT_EMAIL}`} className="text-link">{CONTACT_EMAIL}</a>.</p>
            </div>
          </div>
          <aside className="card rules-card" aria-labelledby="rules-title">
            <h3 id="rules-title" className="title3">What PLUG does not do</h3>
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
