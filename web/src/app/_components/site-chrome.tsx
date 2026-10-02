import Link from "next/link";
import { Logo } from "./brand-art";

// There is no sign-up endpoint yet, so the one call to action leads to Support,
// which carries the operator's confirmed contact address.
export const JOIN_HREF = "/support#join";
export const JOIN_LABEL = "Ask to join the private test";
export const CONTACT_EMAIL = "privacy@plugapp.com";

// Figure 14 header: logo left, section links and the join action right. The header
// action is the secondary style so each page keeps exactly one primary button.
export function SiteHeader() {
  return (
    <header className="site-header">
      <div className="container site-header-inner">
        <Logo />
        <nav aria-label="Main" className="site-nav">
          <ul>
            <li className="site-nav-optional"><Link href="/#how-it-works">How it works</Link></li>
            <li className="site-nav-optional"><Link href="/#truth-labels">Truth labels</Link></li>
            <li className="site-nav-optional"><Link href="/support">Support</Link></li>
            <li>
              <Link href={JOIN_HREF} className="button button-secondary">
                Ask to join
              </Link>
            </li>
          </ul>
        </nav>
      </div>
    </header>
  );
}

const footerGroups = [
  {
    heading: "Product",
    links: [
      { href: "/#how-it-works", label: "How it works" },
      { href: "/#truth-labels", label: "Truth labels" },
    ],
  },
  {
    heading: "Legal",
    links: [
      { href: "/privacy", label: "Privacy" },
      { href: "/terms", label: "Terms" },
    ],
  },
  {
    heading: "Help",
    links: [
      { href: "/support", label: "Support" },
      { href: `mailto:${CONTACT_EMAIL}`, label: "Email PLUG" },
    ],
  },
];

export function SiteFooter() {
  // §15.3: the copyright year is generated, not typed.
  const year = new Date().getFullYear();
  return (
    <footer className="site-footer">
      <div className="container site-footer-inner">
        <div className="footer-about">
          <p className="footer-name">PLUG</p>
          <p>
            Private test in the United States ·{" "}
            <a href={`mailto:${CONTACT_EMAIL}`} className="text-link">{CONTACT_EMAIL}</a>
          </p>
          <p className="footer-fine">© {year} PLUG. Test software; features may change or stop.</p>
        </div>
        <nav aria-label="Information" className="footer-nav">
          {footerGroups.map((group) => (
            <div key={group.heading} className="footer-group">
              <h2 className="overline">{group.heading}</h2>
              <ul>
                {group.links.map((link) => (
                  <li key={link.href}>
                    {link.href.startsWith("mailto:")
                      ? <a href={link.href}>{link.label}</a>
                      : <Link href={link.href}>{link.label}</Link>}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </nav>
      </div>
    </footer>
  );
}
