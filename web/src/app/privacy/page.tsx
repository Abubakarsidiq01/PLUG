import type { Metadata } from "next";
import { LegalPage } from "../_components/legal-page";

export const metadata: Metadata = { title: "Privacy Policy | PLUG" };

export default function Privacy() {
  return (
    <LegalPage title="Privacy Policy" lede="The Privacy Policy is awaiting approval.">
      PLUG is being tested privately. The approved policy will describe the information
      collected, its uses, retention, and how to exercise your privacy rights. This page is a
      placeholder, not a published policy.
    </LegalPage>
  );
}
