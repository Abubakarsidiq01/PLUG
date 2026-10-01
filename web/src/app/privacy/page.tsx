import type { Metadata } from "next";
import { LegalPage } from "../_components/legal-page";
import { LegalCopy } from "../_components/legal-copy";
import legal from "../../content/legal-starter.json";

export const metadata: Metadata = { title: "Privacy Policy | PLUG" };

export default function Privacy() {
  return (
    <LegalPage title="Privacy Policy" lede="Private-test starter draft · September 30, 2026">
      <LegalCopy sections={legal.privacy.sections} />
    </LegalPage>
  );
}
