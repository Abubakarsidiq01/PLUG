import type { Metadata } from "next";
import { LegalPage } from "../_components/legal-page";

export const metadata: Metadata = { title: "Support | PLUG" };

export default function Support() {
  return (
    <LegalPage title="Support" lede="Testing PLUG? Contact the person who invited you.">
      Include what you were trying to do, when it happened, and a request ID if the app shows
      one. Never send passwords, sign-in codes, or session tokens. A public support channel will
      be listed here before launch.
    </LegalPage>
  );
}
