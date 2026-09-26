import type { Metadata } from "next";
import { LegalPage } from "../_components/legal-page";

export const metadata: Metadata = { title: "Terms of Service | PLUG" };

export default function Terms() {
  return (
    <LegalPage title="Terms of Service" lede="The Terms of Service are awaiting approval.">
      This page reserves the address used by the app’s onboarding flow. It is not the published
      agreement. Public registration remains unavailable until the approved terms and consent
      version are published together.
    </LegalPage>
  );
}
