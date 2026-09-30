import type { Metadata } from "next";
import localFont from "next/font/local";
import "./globals.css";
import Link from "next/link";
import { PlugMark } from "./_components/brand-art";

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

export const metadata: Metadata = {
  title: "PLUG",
  description: "Ask for what you need; get real, verified availability back.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={plexSans.variable}>
      <body>
        {children}
        <footer className="site-footer">
          <div className="site-footer-inner">
            <p className="footer-brand">
              <PlugMark className="footer-mark" />
              <span>PLUG</span>
            </p>
            <nav aria-label="Information">
              <Link href="/">PLUG home</Link>
              <Link href="/privacy">Privacy</Link>
              <Link href="/terms">Terms</Link>
              <Link href="/support">Support</Link>
            </nav>
          </div>
        </footer>
      </body>
    </html>
  );
}
