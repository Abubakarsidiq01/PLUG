import type { Metadata } from "next";
import { LegalPage } from "../_components/legal-page";
import legal from "../../content/legal-starter.json";

export const metadata: Metadata = {
  title: "Terms of Service",
  description: "The starter terms for PLUG's invited private test: what the test service does, acceptable use, and your rights.",
};

export default function Terms() {
  return (
    <LegalPage
      title="Terms of Service"
      lede="Starter draft for private-test review · September 30, 2026"
      sections={legal.terms.sections}
    />
  );
}
