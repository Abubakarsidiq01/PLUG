import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Playwright's webServer drives the dev server from 127.0.0.1; without this,
  // Next.js blocks the HMR cross-origin request as a safety default.
  allowedDevOrigins: ["127.0.0.1"],
};

export default nextConfig;
