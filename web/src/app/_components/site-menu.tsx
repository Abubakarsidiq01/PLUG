"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";

// Below 768px the section links fold into this disclosure. Escape closes it and returns
// focus to the button; choosing a link closes it. Without JavaScript the footer still
// carries every link.
export function SiteMenu({ links }: { links: { href: string; label: string }[] }) {
  const [open, setOpen] = useState(false);
  const button = useRef<HTMLButtonElement>(null);
  const panel = useRef<HTMLUListElement>(null);

  useEffect(() => {
    if (!open) return;
    panel.current?.querySelector("a")?.focus();
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      setOpen(false);
      button.current?.focus();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open]);

  return (
    <div className="site-menu">
      <button
        ref={button}
        type="button"
        className="button button-secondary site-menu-toggle"
        aria-expanded={open}
        aria-controls="site-menu-panel"
        onClick={() => setOpen(!open)}
      >
        Menu
      </button>
      <ul id="site-menu-panel" ref={panel} className="site-menu-panel" hidden={!open}>
        {links.map((link) => (
          <li key={link.href}>
            <Link href={link.href} onClick={() => setOpen(false)}>{link.label}</Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
