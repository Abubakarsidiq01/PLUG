// Web copies of design/brand/plug-mark.svg and design/brand/neighbourhood.svg, the
// same artwork the iOS welcome screen uses. They draw in currentColor so the colour
// comes from design tokens in CSS rather than a hex value in markup. Both are
// decorative: the text next to them carries the meaning, so they are hidden from
// assistive technology.

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

export function Neighbourhood({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 384 128" aria-hidden="true" focusable="false">
      <g fill="none" stroke="currentColor" strokeWidth="1.25" strokeLinecap="round" strokeLinejoin="round">
        <path d="M0 120h384M14 120V86h34v34M10 86l21-16 21 16M24 120v-16h12v16M24 92h5m7 0h5M60 120V48h38v72M66 48v-8h26v8M68 58h6v8h-6zm16 0h6v8h-6zM68 78h6v8h-6zm16 0h6v8h-6zM68 98h6v8h-6zm16 0h6v8h-6zM112 120V78h48v42M108 78h56l-7-14h-42l-7 14ZM118 92h13v15h-13zM140 120V92h13v28M171 120V57h33v63M177 57V40h21v17M182 40V30h11v10M180 68h5v8h-5zm12 0h5v8h-5zM180 88h5v8h-5zm12 0h5v8h-5zM180 120v-13h15v13M218 120V94h40v26M214 94l24-21 24 21M228 120v-17h10v17M246 102h5v7h-5zM272 120V66h44v54M276 66V54h36v12M282 78h8v9h-8zm16 0h8v9h-8zM282 98h8v9h-8zm16 0h8v9h-8zM339 120v-18m0-31c-13 0-18 8-15 15-10 7-4 18 6 18h20c10 0 15-11 6-18 2-8-5-15-17-15ZM360 120V96h24M371 103v9m8-9v9" />
        <g className="neighbourhood-pin">
          <path d="M233 60s-9-10-9-16a9 9 0 0 1 18 0c0 6-9 16-9 16Z" />
          <circle cx="233" cy="44" r="3" />
        </g>
      </g>
    </svg>
  );
}

// The app's name, centred above each public page: the mark, then the wordmark.
export function Brand() {
  return (
    <p className="brand">
      <PlugMark className="brand-mark" />
      <span>PLUG</span>
    </p>
  );
}
