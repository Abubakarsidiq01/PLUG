# Photo and illustration credits (iOS app)

## Photos

The iOS app ships no photographs. On 2026-11-17 the owner asked for illustrations instead of
photos, the way service apps such as Uber and Lyft present their categories, and every
`Photo*.imageset` was removed from `ios/Plug/Resources/Assets.xcassets`:

| Removed asset | Was | Replaced by |
| --- | --- | --- |
| PhotoBarber | Unsplash, Obi (@obionyeador) | IllHairBeauty |
| PhotoHomeHelp | Unsplash, Annie Gray (@anniegray) | IllHomeHelp |
| PhotoTech | Unsplash, Samsung Memory (@samsungmemory) | IllTech |
| PhotoPlaces | Unsplash, Dale Honeycutt (@cdaleh) | IllPlaces |
| PhotoStreet | Unsplash, Daniel (@unsplashbydan) | IllKnowBefore |
| PhotoTailor | Unsplash, Nathan Dumlao (@nate_dumlao) | IllOfferService |
| PhotoBarista | Unsplash, Brooke Cagle (@brookecagle) | IllHeroStreet with IllHeroPin (Welcome) |

Earlier removals: `PhotoBraids` and `PhotoShopFront` (2026-11-16), and the AI-generated
`AskBarber` and `ServiceConnection`.

## Illustrations

Every illustration is original work drawn for PLUG by hand as SVG. None is stock art, traced
from another product, or AI-generated. Sources live in `design/illustrations/`; each asset
catalogue imageset holds an exact copy of its source SVG with `preserves-vector-representation`
on, so the art stays sharp at every size and Dynamic Type setting.

Style rules, so new art matches: PLUG palette only (cream #FFF4EC and #FFFBF7, sand #F1E6D8,
#E4D3BE and #D6C1A6, espresso #2B1D14, #4A3628 and #1A110B, forest #1F4D3A, #2E6A51 and
#163829, brass #A9793A, #C79A5B and #87602C); flat fills, no gradients, no outlines except
window frames; light from the top left, so right-hand faces take the darker tone; one soft
ground shadow ellipse in #E4D3BE; 96 x 96 viewBox for tiles.

| Asset | Source | Where it appears |
| --- | --- | --- |
| IllHairBeauty | `design/illustrations/hair-beauty.svg` (scissors and comb) | Ask home, "Hair & beauty" tile |
| IllHomeHelp | `home-help.svg` (toolbox, wrench, hammer) | Ask home, "Home help" tile |
| IllTech | `tech.svg` (cracked phone, screwdriver) | Ask home, "Tech" tile |
| IllPlaces | `places.svg` (storefront, map pin) | Ask home, "Places" tile |
| IllKnowBefore | `know-before.svg` (clock over a queue line) | Ask home, "Know before you go" row |
| IllOfferService | `offer-service.svg` (apron with a price tag) | Ask home, "Do you offer a service?" row |
| IllHeroStreet | `hero-street.svg` (a street of local businesses, a van arriving) | Ask home header, Welcome header |
| IllHeroPin | `hero-pin.svg` (brass map pin) | Drops onto the cafe in the street, once |
| IllActivity | `activity.svg` (clipboard) | Activity empty state |
| IllInbox | `inbox.svg` (envelope) | Provider Inbox empty state |

The illustrations are decorative. VoiceOver skips them, and they are never shown as a
provider's own work, on an offer, or as proof of anything a provider or place claims.
