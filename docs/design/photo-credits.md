# Photo credits (iOS app)

Every photograph in `ios/Plug/Resources/Assets.xcassets/Photo*.imageset` is a real photograph
taken by the person named below. None is AI-generated. Each was downloaded from its Unsplash page
at 1200 px, then resized and recompressed with `sips` (max 1200 px long edge, JPEG quality 66, under 250 KB).
No other edits were made.

All are used under the [Unsplash License](https://unsplash.com/license): free to use, including
commercially, with no permission needed. Attribution is not required; we give it anyway. The
license does not allow selling the photos unaltered or using them to build a competing service.

The photos are decorative. They are never shown as a provider's own work, on an offer, or as
proof of anything a provider or place claims.

PLUG is tested in Austin, Texas, so every photo shows an American setting or a setting that
does not read as anywhere in particular. On 2026-11-16 eight photos set in Lagos, Dar es Salaam
and other non-US places were replaced. PLUG is a service app, so photos are rare: one large
photo on Welcome and small thumbnails in the Ask service grid. Results, offers, Activity,
Profile, Inbox and empty states show no stock photos. PhotoBraids and PhotoShopFront were
removed from the asset catalogue when their empty states lost their photos.

| Asset | Subject (as the source page describes it) | Photographer | Source page | Where it appears |
| --- | --- | --- | --- | --- |
| PhotoBarber | Man cutting hair (Virginia, USA) | Obi (@obionyeador) | https://unsplash.com/photos/man-cutting-hair-man--sRVfY0f2d8 | Ask home, "Hair & beauty" thumbnail |
| PhotoHomeHelp | Man standing in front of a miter saw, in a house | Annie Gray (@anniegray) | https://unsplash.com/photos/man-standing-infront-of-miter-saw-WEWTGkPUVT0 | Ask home, "Home help" thumbnail |
| PhotoTech | A person working on a laptop with a screwdriver | Samsung Memory (@samsungmemory) | https://unsplash.com/photos/a-person-working-on-a-laptop-with-a-screwdriver-6RcDLyy0s1I | Ask home, "Tech" thumbnail |
| PhotoPlaces | The Texas State Capitol in Austin (Austin, TX, USA) | Dale Honeycutt (@cdaleh) | https://unsplash.com/photos/UnRQMowT5rM | Ask home, "Places" thumbnail |
| PhotoStreet | A group of people sitting at tables under umbrellas (Austin, TX, USA) | Daniel (@unsplashbydan) | https://unsplash.com/photos/a-group-of-people-sitting-at-tables-under-umbrellas-8aE2acBzTlw | Ask home, "Know before you go" thumbnail |
| PhotoTailor | A barista in a plaid shirt and apron using a tablet at a wooden counter | Nathan Dumlao (@nate_dumlao) | https://unsplash.com/photos/barista-using-tablet-in-coffee-shop-X_bbCAYzlTs | Ask home, "Do you offer a service?" thumbnail |
| PhotoBarista | Man in blue and white plaid dress shirt standing in front of table (coffee shop) | Brooke Cagle (@brookecagle) | https://unsplash.com/photos/man-in-blue-and-white-plaid-dress-shirt-standing-in-front-of-table-UYaBqDP6JoY | Welcome screen, the one large photo |

The asset names are older than the photos (PhotoTailor now shows a café owner); they were kept so
no code had to change. Small product markings remain on two photos:
a tool maker's name on the saw in PhotoHomeHelp and a model number on the drive in PhotoTech.
Neither is legible at the size the app shows them.

Removed: `AskBarber` and `ServiceConnection` were AI-generated images. They were not referenced by
any Swift file and have been deleted from the asset catalogue.

When adding a photo: take it from a free Unsplash License or Pexels License page (not Unsplash+),
copy the photographer and URL from that page exactly, and add a row here in the same change.
