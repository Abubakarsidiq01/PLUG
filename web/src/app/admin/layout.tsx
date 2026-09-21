// src/proxy.ts allows only the login placeholder during Phase 0. This layout
// is also used by that public login page; it is not an authorization boundary.
export default function AdminLayout({ children }: LayoutProps<"/admin">) {
  return <div className="admin-shell">{children}</div>;
}
