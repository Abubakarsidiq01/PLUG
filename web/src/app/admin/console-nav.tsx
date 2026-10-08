import { signOut } from "./actions";

// The staff console's own bar: its two sections on the left, Sign out on the right. Shared by
// /admin and /admin/staff so the two pages read as one tool, not two stacked links.
export function ConsoleNav({ current }: { current: "inspector" | "staff" }) {
  const sections = [
    { key: "inspector", href: "/admin", label: "Classifier inspector" },
    { key: "staff", href: "/admin/staff", label: "Staff" },
  ] as const;
  return (
    <nav className="console-bar" aria-label="Staff console">
      <ul className="console-sections">
        {sections.map((section) => (
          <li key={section.key}>
            <a href={section.href} aria-current={section.key === current ? "page" : undefined}>{section.label}</a>
          </li>
        ))}
      </ul>
      <form action={signOut}>
        <button type="submit" className="console-sign-out">Sign out</button>
      </form>
    </nav>
  );
}
