import type { Metadata } from "next";
import { IBM_Plex_Sans } from "next/font/google";
import "./globals.css";

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
      <body>{children}</body>
    </html>
  );
}
