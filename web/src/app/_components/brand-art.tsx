import Link from "next/link";

// Web copy of design/brand/plug-mark.svg (256 grid). Draws in currentColor so the
// colour comes from design tokens in CSS. Decorative: the logotype carries the name.
const BODY =
  "M50 32H134A72 72 0 0 1 134 176H96V224H50ZM134 60A44 44 0 1 1 134 148A44 44 0 1 1 134 60Z";

export function PlugMark({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 256 256" aria-hidden="true" focusable="false">
      <path fill="currentColor" fillRule="evenodd" d={BODY} />
      <circle fill="currentColor" cx="134" cy="104" r="21" />
    </svg>
  );
}

// The one brand moment on load: dot, ring, then the P closes around them. Pure CSS
// (globals.css .mark-anim). The static markup is the final frame, so reduced motion
// shows the finished mark.
export function PlugMarkAnimated({ className }: { className?: string }) {
  return (
    <svg className={`mark-anim ${className ?? ""}`} viewBox="0 0 256 256" aria-hidden="true" focusable="false">
      <circle className="mark-ring" cx="134" cy="104" r="44" fill="none" stroke="currentColor" strokeWidth="3" />
      <path className="mark-body" fill="currentColor" fillRule="evenodd" d={BODY} />
      <circle className="mark-dot" fill="currentColor" cx="134" cy="104" r="21" />
    </svg>
  );
}

// The PLUG logotype (design/brand/plug-logotype.svg) as paths. The logo always links
// to / (§15.3). The accessible name is a hidden span, not aria-label, so the link
// name and visible content cannot mismatch.
export function Logo() {
  return (
    <Link href="/" className="logo">
      <svg className="logo-type" viewBox="34 0 674 256" aria-hidden="true" focusable="false">
        <g fill="currentColor">
          <path fillRule="evenodd" d={BODY} />
          <circle cx="134" cy="104" r="21" />
          <path transform="translate(234 0)" d="M0 32H44V136H100V176H0Z" />
          <path transform="translate(358 0)" d="M0 32H44V112A22 22 0 0 0 88 112V32H132V112A66 66 0 0 1 0 112Z" />
          <g transform="translate(514 0)">
            <path d="M126.3 51.7A74 74 0 1 0 148.0 104.0L104.0 104.0A30 30 0 1 1 95.2 82.8Z" />
            <path d="M90 104H148V140H90Z" />
          </g>
        </g>
      </svg>
      <span className="visually-hidden">PLUG home</span>
    </Link>
  );
}
