import type { Metadata } from "next";
import { LegalPage } from "../_components/legal-page";
import legal from "../../content/legal-starter.json";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "How PLUG handles information during its private test: what is processed, why, for how long, and how to ask about it.",
};

export default function Privacy() {
  return (
    <LegalPage
      title="Privacy Policy"
      lede="Starter draft for private-test review · September 30, 2026"
      sections={legal.privacy.sections}
    />
  );
}
