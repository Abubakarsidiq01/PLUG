import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { connection } from "next/server";
import { apiOrigin } from "@/lib/staff-console";
import { AcceptForm } from "./accept-form";

// Where an emailed staff invitation lands (ADR-013): <console>/staff/accept#token=sti_…
// It answers 404 unless the server has PLUG_API_URL, like the rest of the staff console.
export const metadata: Metadata = {
  title: "Staff invitation",
  robots: { index: false, follow: false },
};

export default async function StaffAccept() {
  await connection();
  if (apiOrigin() === null) notFound();
  return (
    <main className="notice-page">
      <div className="container">
        <div className="card notice-card">
          <p className="overline">Admin</p>
          <h1 className="title1">Accept your staff invitation</h1>
          <p>Choose a password. After this you sign in with your email, this password and a code we email you each time.</p>
          <AcceptForm />
        </div>
      </div>
    </main>
  );
}
