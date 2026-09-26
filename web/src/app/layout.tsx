import type { Metadata } from "next";
import { IBM_Plex_Sans } from "next/font/google";
import "./globals.css";
import Link from "next/link";

// tokens.json._rules: "Web uses IBM Plex Sans. Inter as a default is banned."
const plexSans = IBM_Plex_Sans({
  variable: "--font-plex-sans",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
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
          <nav aria-label="Information">
            <Link href="/">PLUG home</Link>
            <Link href="/privacy">Privacy</Link>
            <Link href="/terms">Terms</Link>
            <Link href="/support">Support</Link>
          </nav>
        </footer>
      </body>
    </html>
  );
}
