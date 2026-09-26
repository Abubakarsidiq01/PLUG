# PLUG welcome and sign-in design

Design authority: PLUG_Production_Master_Manual_v3.docx, Figure 10 (core app
flow), Figure 7 (tokens), Figure 8 (components), and Part II §§9–11 and 16.

The welcome composition follows Figure 10: a centred P mark, PLUG wordmark,
“Real-time truth. Better local decisions.”, a quiet neighbourhood streetscape,
Get started as the blue primary action, and I have an account beneath it.
Guest access and the working private-testing legal notices are retained.
The previous generic headline and conversation-diagram composition were rejected
by the user and superseded; their screenshots are historical evidence only.

plug-mark.svg redraws the blueprint's P-shaped connection mark in the flat brand
colour. neighbourhood.svg is an original line illustration following the local
streetscape treatment in the wireframe. It contains no business identities,
ratings, fabricated availability or activity. Both assets load locally. The app
icon and native launch image reuse the same mark.

The shared tokens supply colours, 16-point phone gutters, spacing, corner radii,
and base type sizes. SwiftUI scales body, labels and headings with Dynamic Type.
Button targets are at least 44 points, corners are 8 points, and one action is
primary. Field labels remain visible above the inputs. Artwork yields to content
at accessibility sizes, and all content scrolls when it exceeds the viewport.
Screen changes use 180ms easing; press feedback darkens over 120ms. Reduce Motion
disables both. There is no entrance delay, scroll reveal or continuous animation.

The sign-in wireframe's generic email/password fields are not fake controls in
this passwordless implementation. Google is the configured provider; Apple/phone
are enabled only when configured; phone has an explicit availability notice during setup. Recovery follows the chosen provider. This preserves
the user's earlier requirement for separate method-specific flows.

Research references inspected: https://uiverse.io, https://animejs.com,
https://gsap.com and https://motionsites.ai. The blueprint's actual illustrated
composition takes priority over those references. No web animation library is
added to the native app.

Source vectors live here. Run `node design/generate-brand.mjs` with the project
Node runtime to export native assets and the app icon. The exporter checks artwork
colours against design/tokens.json. Run `node design/generate-tokens.mjs` to export
the shared token values, including Dynamic Type base sizes.
