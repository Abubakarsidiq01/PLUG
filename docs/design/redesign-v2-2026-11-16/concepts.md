# PLUG redesign v2: three concepts

Status: proposal for the owner to pick one. Not implemented, not reviewed against the section 16.8 design gate, no app code touched. All content is synthetic test-fixture content (Fade City Barbershop, Sharp Cuts Studio, Walmart on Ben White). HTML sources: `/Users/abubakar-sidiqbolakale/.claude/jobs/a57d738b/tmp/v2-concepts/` (`c1|c2|c3.*`, `build.py`, `render.mjs`).

Each folder under `concepts/` holds: `00-board.png` (1600 wide), `01-home` to `06-profile` (390x844 at 2x), `07-web-hero`, `08-admin-console` (1280x800 at 2x), `motion.webm` (about 6.5 s, 640x1260) and `motion-storyboard.png` (six frames of the clip).

## Rules held in all three (product honesty, not style)

- Truth labels are icon plus word plus edge treatment, so they read without colour: Confirmed (solid check), Recent (clock), Estimated (tilde over a line), Unknown (dashed circle, dashed edge), Not verified (globe, dashed edge, hatched fill; the only hatched item anywhere).
- Web answer is always a separate block labelled "Not verified", with "From the web, not from people nearby".
- Test mode is one persistent marker on every screen, with the full sentence behind a tap. No repeated disclosure sentences. Reference codes appear only behind a "Details" link (iOS) and in the staff console, where the request reference is the working key.
- Only numbers in the fixture appear: $30, $35, 0.53 mi, 1.30 mi, "3 notified, 1 replied", "12-15 min". No scores, reviews, stars, user counts or logos. Offers show no score because none is in the fixture.
- Colour pairs below are measured WCAG contrast. All text pairs are 4.5:1 or better. Targets are 44pt or taller. Dynamic Type: layouts use wrapping text and fixed-height-free cards; the tightest spots (tab bar labels, chips row) need a real device check.
- Reduced motion: every animation has a stated fallback below. The stills were rendered with `prefers-reduced-motion: reduce`, so they show those fallbacks.
- Copy flagged for owner and product review (invented wording, not from the contract): "Nobody nearby has answered. PLUG will not guess.", "This price is an estimate. The shop has not confirmed it for today.", "Offers arrive as people answer", "Work from providers / Their own photos", "Receive asks". Skill names Barber, Braids, Laptop repair come from `contracts/skills.yaml`.

## 1. Signal

**Idea.** A loud, ownable pink and big heavy type make PLUG recognisable in a feed or a pitch deck. Buttons are physical keycaps with a hard bottom edge that drops when pressed. The home screen is a full field of colour with one question. "People being asked" is shown as three nodes: the replied one filled with a check, the others pinging with rings until they answer. Bricolage Grotesque is the only family.

**Palette** (contrast measured)

| Role | Hex | OKLCH |
| --- | --- | --- |
| Signal | #FF2E8B | 66% 0.25 1 |
| Ink | #15110F | 18% 0.01 48 |
| Cream | #FFF4EC | 97% 0.02 59 |
| Deep (text on light) | #B5064C | 50% 0.20 8 |
| Truth: Confirmed / Recent / Estimated / Unknown | #0E7A43 / #0B6E7A / #7A4E00 / #4F4A45 on #DDF3E6 / #D5EEF1 / #FBE9BE / #ECE8E4 | |
| Error | #B3261E | 50% 0.18 29 |

Pairs: Ink on Signal 5.38, Ink on Cream 17.34, Deep on Cream 6.27, White on Deep 6.78, Confirmed 4.64, Recent 4.92, Estimated 6.00, Unknown 7.19, Error on Cream 6.04. White on Signal is 3.5, so it is banned. Pink does not collide with the label colours; it is the closest to error red (hue 1 against 29, much lighter, never used for text on light), so errors also carry an icon and the word "Error".

**Type.** Bricolage Grotesque 500/700/800 (Google Fonts, OFL). Display 40 to 58 pt at 800 with tight tracking; body 17 pt.

**Motion personality.** Springy and physical. Press: 80 ms, key drops 4 pt. Sheets and offer cards: spring, about 0.6 s, slight overshoot (response 0.45, damping 0.7). Asking: node rings ping 1.8 s loops; ripple rings on home 4 s. Offers arrive with a rise and scale. Haptic: light impact on press, success on first offer. Reduced motion: no springs or loops; rings become static rings, cards and sheets cross-fade in 150 ms, keys still show the pressed state but without travel (colour change only).

**Truth labels.** Bordered 2 px chips, solid for known states, dashed for Unknown and Not verified. Unknown and Not verified sit on grey so they never borrow the pink.

**Test mode.** An ink tab hangs off the right edge under the status bar. **Reference codes:** behind "Details" in the offer sheet and profile.

**Rules it breaks.** Brand colour (ink on paper only becomes a pink brand), gradients unused but hard shadows and thick outlines added, no shadows rule replaced by keycap edges, motion goes from almost none to springy. No imagery.

**Risk.** Pink plus thick outlines can read as playful or consumer-social, which may undercut trust for money-adjacent asks; and the look is trend-adjacent (neo-brutalist), so it needs discipline to avoid ageing quickly.

## 2. Tactile

**Idea.** PLUG lives on a map of your neighbourhood. Home is the map with a draggable bottom sheet holding the ask field; offers are price pins that drop onto the map and raised cards in the sheet. Material carries meaning: answers from people are raised cards, Unknown is a sunken well, a web answer is a flat dashed hatched note. Warm sand, paper and walnut. Cobalt is reserved for "you" (map dot, links, focus).

**Palette**

| Role | Hex | OKLCH |
| --- | --- | --- |
| Paper | #FBF7EF | 98% 0.01 85 |
| Sand (map, wells) | #E9DFCC | 91% 0.03 84 |
| Walnut (ink, buttons) | #2B2118 | 26% 0.02 64 |
| Mute | #5B4D3F | 43% 0.03 67 |
| You, cobalt | #2A5BD7 | 52% 0.20 264 |
| Truth and error | same as Signal | |

Pairs: Paper on Walnut 14.74, Walnut on Sand 11.92, Mute on Paper 7.62, Cobalt on Paper 5.50, White on Cobalt 5.87, Error on Paper 6.12; labels as in Signal.

**Type.** Figtree 400 to 800 (OFL). Rounded, friendly, compact in dense cards. Body 17 pt.

**Motion personality.** Physical and draggable. Sheets: detents at peek, half and full, spring (response 0.5, damping 0.85), velocity-aware. Pins drop with a 0.7 s bounce; asking waves expand from your dot every 2.6 s; the progress bar has a travelling segment. Buttons sink 2 pt with an inner shadow. Reduced motion: no drop, bounce, waves or travelling segment (waves become two static rings); sheets move by detent with a 200 ms ease and no overshoot.

**Truth labels.** Chips plus material: raised (person), sunken (Unknown), flat hatched dashed (web). Material is a second cue, never the only one.

**Test mode.** A taped paper label with a dashed edge floats top right over the map. **Reference codes:** behind "Details".

**Rules it breaks.** Shadows (real, soft, purposeful elevation), imagery (a drawn map surface as the home canvas), colour (cobalt role, warm materials), motion (drag, drop, waves). It needs a map: the mock uses an invented schematic; a real build needs a map provider, location permission handling and a decision on street-label sources (new dependency and privacy review, not in the current contracts).

**Risk.** Biggest build cost and the most dependencies (map SDK, location, offline and low-data states); a map makes "Unknown place" answers look empty if no pin data exists.

## 3. Editorial

**Idea.** The people behind the price come first. Generous frames for each provider's own photos (placeholders labelled "provider photo"; the profile has "Your work" with Add photo), a characterful serif for names and prices, hairline rules, and a calm indigo for action. Flat, quiet, trustworthy, closer to a good magazine or a well-made service directory than an app kit.

**Palette**

| Role | Hex | OKLCH |
| --- | --- | --- |
| Paper | #F5EFE4 | 95% 0.02 83 |
| Ink (green-black) | #1D2420 | 25% 0.01 160 |
| Indigo (action) | #2F3E7C | 39% 0.11 271 |
| Clay tint (photo frames) | #E9D3BF | 88% 0.04 65 |
| Sage tint | #CAD3BF | 85% 0.03 127 |
| Mute | #5F5A50 | 47% 0.02 85 |
| Truth and error | same as Signal | |

Pairs: Ink on Paper 13.84, Indigo on Paper 8.73, Paper on Indigo 8.73, Mute on Paper 5.99, Ink on Clay 10.97, Ink on Sage 10.25, Error on Paper 5.71.

**Type.** Fraunces 400/600/700 for display and names (OFL) with Hanken Grotesk 400 to 700 for text (OFL). Display 36 to 48 pt; "Unknown" is set large in italic so honesty is a typographic event. Body 17 pt.

**Motion personality.** Calm. Cross-fades 450 to 900 ms, ease (0.3, 0, 0.2, 1), 14 pt rise on arrival; the progress line draws over 1.6 s with breathing markers while waiting. Shared element: the offer's photo slot grows into the sheet header. Press: colour darkens 6 percent over 250 ms. Reduced motion: fades only (no rise), no breathing, shared element becomes a plain cross-fade.

**Truth labels.** Small stamps with a 1.5 px rule, like a photo caption; dashed for Unknown and Not verified. Activity rows lead with a serif italic date.

**Test mode.** A dashed stamp in the right margin under the status bar. **Reference codes:** behind "Details".

**Rules it breaks.** Imagery (photo slots are now first-class, so real provider photos and a moderation and storage path are needed: no contract exists yet), brand colour (indigo plus clay and sage tints), type (a serif), motion (calm but present). No shadows, no gradients.

**Risk.** Looks empty or unfinished when providers have no photos (most test providers will not), and photo upload is new scope with moderation and consent questions.

## Recommendation

Pick **Signal** for the public brand and the pitch, but borrow two things from the others: Tactile's material logic for answers (raised for people, sunken for Unknown, flat hatched for the web) and a photo slot on the offer sheet only (not on lists) from Editorial, switched on once real provider photos exist.

Why: Signal is the only concept that is distinctive in a thumbnail, works with no imagery or map data (which PLUG does not have yet), costs the least to build in SwiftUI and Next.js, and puts the honest states (Unknown, Not verified, Estimated) in big, legible type. Tactile is the most "real" but depends on a map provider and location data that are not in the contracts. Editorial is the most trustworthy but only looks good once providers upload photos, which is new scope. If the owner values investor wow above build cost, pick Tactile; if provider trust matters most, pick Editorial after a photo contract exists.

## Not done or not verified

- No real device, VoiceOver, Dynamic Type at the largest sizes, or contrast check on rendered screenshots; contrast figures are computed from the hex values.
- Motion clips are CSS approximations of the springs; real SwiftUI spring values need tuning on device. Clips were recorded at 640x1260 (no ffmpeg available, so no MP4 or GIF); the storyboard PNG is the quick look.
- Tactile's web hero map has visible seams where map tiles repeat, and its map is an invented schematic. Signal's and Editorial's web heroes use a phone mock and photo placeholders, not live product.
- Sheet-over-results and the web hero phone are CSS composites, not interactive.
