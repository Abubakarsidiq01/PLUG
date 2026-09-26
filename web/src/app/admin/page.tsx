import { redirect } from "next/navigation";

// Enforce the closed boundary in the server page as well as the proxy. Phase 1
// issues no admin scope; a cookie alone must never grant administrative access.
export default function AdminHome(): never {
  redirect("/admin/login?from=%2Fadmin");
}
