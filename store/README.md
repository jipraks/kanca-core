# Play Store listing art

Art that goes in the Play Console and nowhere else. It is here so that it is
version-controlled and rebuildable, and it is excluded from the Android export
(`exclude_filter`) so that it never ships inside the app.

| File | Play requirement |
|---|---|
| `feature_graphic_1024x500.png` | 1024 × 500, 24-bit PNG or JPEG, no transparency |

The app icon Play asks for is `assets/ui/brand/app_icon_512.png` — it lives with
the other icons rather than here, because the game uses it too as
`application/config/icon`.

Rebuild both with `tools/build_brand_images.tscn`; see the brand tooling section
in [`../README.md`](../README.md). Nothing in this folder should be edited by
hand — it is output.

Still outstanding for PLAN.md §13.2: at least four screenshots, taken on a real
device once the Dapur is in.
