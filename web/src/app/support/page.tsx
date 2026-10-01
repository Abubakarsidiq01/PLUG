import type { Metadata } from "next";
import { LegalPage } from "../_components/legal-page";
import { LegalCopy } from "../_components/legal-copy";
import legal from "../../content/legal-starter.json";

export const metadata: Metadata = { title: "Support | PLUG" };

export default function Support() {
  return (
    <LegalPage title="Support" lede="Private-test starter draft · September 30, 2026">
      <LegalCopy sections={legal.support.sections} />
    </LegalPage>
  );
}
