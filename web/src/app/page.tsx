import { Brand, Neighbourhood } from "./_components/brand-art";

// Phase 0 public shell only (manual.docx P0.S2: "Do not build feature UI yet").
// Copy stays honest per §15 and docs/CONTRIBUTOR_WORKFLOW.md rule 4: no invented
// metrics, counters, testimonials or claims about availability that isn't real yet,
// and no call to action that leads nowhere. The steps describe how PLUG is designed
// to work, not a service that is live today.
const steps = [
  {
    title: "Ask",
    body: "Say what you need and where, in your own words.",
  },
  {
    title: "PLUG checks",
    body: "PLUG asks nearby businesses directly, instead of relying on old listings.",
  },
  {
    title: "Decide",
    body: "Real replies come back with how recent they are, so you can choose with confidence.",
  },
];

export default function Home() {
  return (
    <main className="public-shell home">
      <section className="hero" aria-labelledby="home-title">
        <Brand />
        <p className="status-pill">
          <span className="status-dot" aria-hidden="true" />
          In private development
        </p>
        <p className="tagline">Real-time truth. Better local decisions.</p>
        <h1 id="home-title">Ask for what you need. Get real, verified availability back.</h1>
        <p className="lede">There is nothing to sign up for yet.</p>
      </section>

      <div className="streetscape">
        <Neighbourhood className="streetscape-art" />
      </div>

      <section className="steps" aria-labelledby="steps-title">
        <h2 id="steps-title">How PLUG is designed to work</h2>
        <ol>
          {steps.map((step, index) => (
            <li key={step.title} className="step">
              <span className="step-number" aria-hidden="true">{index + 1}</span>
              <h3>{step.title}</h3>
              <p>{step.body}</p>
            </li>
          ))}
        </ol>
      </section>
    </main>
  );
}
