import type { Metadata } from "next";
import Link from "next/link";

// §15.2: custom, branded 404 that links home and to support; not indexed.
export const metadata: Metadata = {
  title: "Page not found",
  robots: { index: false },
};

export default function NotFound() {
  return (
    <main className="notice-page">
      <div className="container">
        <div className="card notice-card">
          <p className="overline">404</p>
          <h1 className="title1">Page not found</h1>
          <p>There is no page at this address. It may have moved, or the link may be mistyped.</p>
          <p className="notice-actions">
            <Link href="/" className="button button-primary">Back to home</Link>
            <Link href="/support" className="text-link">Contact support</Link>
          </p>
        </div>
      </div>
    </main>
  );
}
