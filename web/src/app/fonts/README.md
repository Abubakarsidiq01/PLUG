# Public Sans

The site uses local Public Sans Latin weights 400, 500, 600 and 700, restored from the
checked-in v4 handoff patch (`@fontsource/public-sans@5.3.0`). Licensed under the SIL Open
Font License 1.1; see OFL-PublicSans.txt. Local files keep the build free of the Google
Fonts network dependency and the Windows Turbopack Google-font resolver failure.

# Bricolage Grotesque

`bricolage-grotesque-variable.ttf` is the display face of the Signal visual system (ADR-015),
copied unchanged from the official Google Fonts repository,
`ofl/bricolagegrotesque/BricolageGrotesque[opsz,wdth,wght].ttf` (SHA-256
`413e7357809ddd12fd80a96a8a396de0e401638d4acd3cb3e37532f0472ac682`), renamed only so
`next/font/local` paths stay plain. Variable axes: opsz 12 to 96, wdth 75 to 100, wght 200 to
800. Licensed under the SIL Open Font License 1.1; see OFL-BricolageGrotesque.txt. The master
copy lives in `design/fonts/bricolage-grotesque/`. Loaded in `layout.tsx` with `next/font/local` as `--font-bricolage`. The Public Sans files above are no longer imported.
