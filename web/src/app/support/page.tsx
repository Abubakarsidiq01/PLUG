import type { Metadata } from "next";
import { LegalPage } from "../_components/legal-page";
import { CONTACT_EMAIL } from "../_components/site-chrome";
import legal from "../../content/legal-starter.json";

export const metadata: Metadata = {
  title: "Support",
  description: "How to contact PLUG about the private test, your account, privacy or a security concern.",
};

// §15.2: Support's one primary action is "Contact support". It opens a real
// mailto: to the operator's confirmed inbox; there is no form or ticket system.
export default function Support() {
  return (
    <LegalPage
      title="Support"
      lede="Starter draft for private-test review · September 30, 2026"
      sections={legal.support.sections}
      action={<a href={`mailto:${CONTACT_EMAIL}`} className="button button-primary">Contact support</a>}
    >
      <section id="join" className="join-note" aria-labelledby="join-h">
        <h2 id="join-h" className="title3">Joining the private test</h2>
        <p>
          PLUG is in an invite-only test on iPhone. There is no sign-up form or waiting list.
          To ask about taking part, as a person or as a local business, email{" "}
          <a href={`mailto:${CONTACT_EMAIL}?subject=PLUG%20private%20test`} className="text-link">{CONTACT_EMAIL}</a>.
          Asking does not guarantee an invitation.
        </p>
      </section>
    </LegalPage>
  );
}
