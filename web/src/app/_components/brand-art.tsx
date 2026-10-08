import Link from "next/link";

// Web copy of design/brand/plug-mark.svg. It draws in currentColor so the colour
// comes from design tokens in CSS rather than a hex value in markup. It is
// decorative: the wordmark next to it carries the name.
export function PlugMark({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 64 80" aria-hidden="true" focusable="false">
      <path
        fill="currentColor"
        fillRule="evenodd"
        d="M14 4H36a24 24 0 0 1 0 48h-8v8c0 12-7 19-19 20V68c5-1 7-4 7-9v-7h-2a8 8 0 0 1-8-8V12a8 8 0 0 1 8-8Zm6 14v20h16a10 10 0 0 0 0-20H20Z"
      />
    </svg>
  );
}

// The PLUG logotype, the same as the app's: the designed P is the letter P, then "LUG",
// in ink (owner decision, 2026-10-08). The logo always links to / (§15.3 launch checklist).
export function Logo() {
  return (
    <Link href="/" className="logo" aria-label="PLUG home">
      <span className="logo-word" aria-hidden="true">
        <PlugMark className="logo-mark" />LUG
      </span>
    </Link>
  );
}
