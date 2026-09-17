// Every route under here is gated by src/middleware.ts. This layout renders
// only after middleware has already confirmed a session cookie is present.
export default function AdminLayout({ children }: LayoutProps<"/admin">) {
  return <div className="admin-shell">{children}</div>;
}
