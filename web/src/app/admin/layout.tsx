import type { Metadata } from "next";

// §15.2: /admin/* is noindex and excluded from the sitemap.
export const metadata: Metadata = {
  title: "Admin",
  robots: { index: false, follow: false },
};

// src/proxy.ts allows only the login shell during Phase 1. This layout
// is also used by that public login page; it is not an authorization boundary.
export default function AdminLayout({ children }: LayoutProps<"/admin">) {
  return <div className="admin-shell">{children}</div>;
}
