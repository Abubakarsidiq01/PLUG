import type { Metadata } from "next";
import localFont from "next/font/local";
import "./globals.css";
import "./signal.css";
import { SiteFooter, SiteHeader } from "./_components/site-chrome";

// ADR-015 Signal: Bricolage Grotesque variable (OFL), bundled locally so builds need no font service.
const bricolage = localFont({
  variable: "--font-bricolage",
  display: "swap",
  src: [{ path: "./fonts/bricolage-grotesque-variable.ttf", weight: "200 800", style: "normal" }],
});

// manual.docx §15.2 title pattern: "<Page> — PLUG".
export const metadata: Metadata = {
  title: { default: "PLUG", template: "%s — PLUG" },
  description:
    "Tell PLUG what you need, your budget and when. It shows who nearby can help, and labels anything it does not know as Unknown.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={bricolage.variable}>
      <body>
        <a href="#main" className="skip-link">Skip to content</a>
        <SiteHeader />
        <div id="main" className="site-main" tabIndex={-1}>
          {children}
        </div>
        <SiteFooter />
      </body>
    </html>
  );
}
