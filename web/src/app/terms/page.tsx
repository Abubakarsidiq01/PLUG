import type { Metadata } from "next";
import { LegalPage } from "../_components/legal-page";
import { LegalCopy } from "../_components/legal-copy";
import legal from "../../content/legal-starter.json";

export const metadata: Metadata = { title: "Terms of Service | PLUG" };

export default function Terms() {
  return (
    <LegalPage title="Terms of Service" lede="Private-test starter draft · September 30, 2026">
      <LegalCopy sections={legal.terms.sections} />
    </LegalPage>
  );
}
