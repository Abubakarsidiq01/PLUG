import type { Metadata } from "next";
import localFont from "next/font/local";
import "./globals.css";
import { SiteFooter, SiteHeader } from "./_components/site-chrome";

// tokens.json._rules: "Web uses IBM Plex Sans. Inter as a default is banned."
const plexSans = localFont({
  variable: "--font-plex-sans",
  display: "swap",
  src: [
    { path: "./fonts/IBMPlexSans-Regular.woff2", weight: "400", style: "normal" },
    { path: "./fonts/IBMPlexSans-Medium.woff2", weight: "500", style: "normal" },
    { path: "./fonts/IBMPlexSans-SemiBold.woff2", weight: "600", style: "normal" },
    { path: "./fonts/IBMPlexSans-Bold.woff2", weight: "700", style: "normal" },
  ],
});

// manual.docx §15.2 title pattern: "<Page> — PLUG".
export const metadata: Metadata = {
  title: { default: "PLUG", template: "%s — PLUG" },
  description:
    "Tell PLUG what you need, your budget and when. It shows who nearby can help, and labels anything it does not know as Unknown.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={plexSans.variable}>
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
