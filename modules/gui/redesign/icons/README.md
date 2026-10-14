# VLC redesign icons

These unmodified SVG assets come from the owner's Figma reference, file
`NbLN6ylrDsmWVVTS8Jo10z`, Page 1. Their original geometry is 24 × 24 pixels.
Playback artwork and library covers in the mockups are sample media; VLC continues
to use the current media and its metadata for those slots.

| File | Figma node | Render transform |
| --- | --- | --- |
| previous.svg | 45:18 | none |
| play.svg | 44:419 | none |
| pause.svg | 44:427 | none |
| next.svg | 45:12 | none |
| audio.svg | 44:407 | none |
| subtitles.svg | 42:398 | none |
| playback-settings.svg | 2230:9222 | none |
| queue.svg | 217:191 | none |
| queue-repeat.svg | 187:471 (Queue 463:831) | flip-x |
| queue-shuffle.svg | 187:475 (Queue 463:831) | flip-x |
| queue-remove.svg | 463:561 (Queue 463:831) | none |
| queue-drag.svg | 463:418 (Queue 463:831) | flip-x |
| folder.svg | 51:808 | flip-x |
| play-accent.svg | I491:2000;3603:12304;848:1707;44:420 | none |
| volume-high.svg | I491:2000;491:1732;182:180 | flip-x |
| volume-background.svg | 244:211 | none |
| volume-fill.svg | 244:214 | none |
| volume-mask.svg | 244:212 | none |
| bookmarks.svg | 2127:7548 | none |
| chapters.svg | 2127:7531 | none |
| add.svg | 463:550 | none |
| fullscreen.svg | 48:54 | none |
| fullscreen-exit.svg | 6031:13553 | none |
| close.svg | 45:40 | none |
| search.svg | 856:2147 | none |
| home.svg | 70:828 | flip-x |
| home-chevron.svg | 71:875 | flip-x for forward navigation |
| library-artist.svg | 858:5155 | none |
| videos.svg | 71:857 (whole component export) | none |
| music.svg | 999:4806 (child 999:4807) | flip-x |
| network.svg | 70:833 (child 70:834) | flip-x |
| playlists.svg | 42:357 (child 42:362) | none |
| recent.svg | 2154:9699 (child 2154:9700) | flip-x |
| library-back.svg | 1106:5646 (71:890) | flip-x |
| library-forward.svg | 1106:5647 (71:887) | flip-x |
| library-more.svg | 2139:8813 | flip-x |
| library-expand.svg | 2139:8814 | flip-x |
| library-sort.svg | 2139:8795 | none |
| library-view.svg | 2139:8796 | none |
| library-search.svg | 2139:8797 | none |
| menu-file.svg | 2461:9644 (menu 6062:13354) | none |
| menu-folder.svg | 2461:9734 (menu 6062:13354) | flip-x |
| menu-network.svg | 2461:9672 (menu 6062:13354) | flip-x |
| menu-disc.svg | 2460:9552 (menu 6062:13354) | none |
| menu-capture.svg | 2493:9342 (menu 6062:13354) | none |
| menu-convert.svg | 2461:9628 (menu 6062:13354) | flip-x |
| menu-recent.svg | 2493:9246 (menu 6062:13354) | flip-x |
| menu-profile.svg | 2493:9300 (menu 6062:13354) | none |
| menu-hotkeys.svg | 2493:9253 (menu 6062:13354) | none |
| menu-customize.svg | 2493:9283 (menu 6062:13354) | flip-x |
| menu-settings.svg | 2493:9293 (menu 6062:13354) | none |
| menu-about.svg | 2461:9651 (menu 6062:13354) | none |
| player-tab-playback.svg | I5187:24601;6073:13945 | none |
| player-tab-video.svg | I2127:7743;999:4811 | flip-x |
| player-tab-audio.svg | I2127:7761;2461:9698 | none |
| player-tab-bookmarks.svg | 6320:13922 | none |
| player-tab-chapters.svg | 2127:7532 | none |
| player-tab-queue.svg | 2127:7524 | none |
| player-tab-subtitles.svg | I2127:7691;42:399 | none |

The four settings-tab assets retain their original 20 × 20 geometry. Queue,
bookmark and chapter tab exports retain their original 24 × 24 geometry, as do
menu assets. The control and menu layers are recolored at
render time for the selected theme; the downloaded SVG files remain unchanged.

The unmodified `settings-*.svg` assets are the exact category, search, close,
chevron and information assets exported from Global Settings (`3046:9282`) and
the corresponding selected-category frames below in that same Figma file.
Category/search/close/chevron assets retain their 24 × 24 geometry; the information
asset is 18 × 18. Default and active variants are separate source assets.

| Category | Selected Figma frame |
| --- | --- |
| General | 3046:9282 |
| Interface | 3046:10057 |
| Privacy | 3062:11911 |
| Controls | 6536:14482 |
| Playback | 3062:12552 |
| Video | 3073:14187 |
| Audio | 3073:15879 |
| Subtitles | 3180:17989 |
| Library | 6542:15251 |
| Network | 6543:15649 |
| Performance | 6571:15958 |
| Recording | 6571:16429 |
| Extensions | 6575:17137 |

`onboarding-cone.svg` is the unchanged 141 × 141 cone from onboarding welcome
frame `1899:3055` (icon instance `1899:3056`).

`onboarding-accent-{orange,red,yellow,green,cyan,blue,purple,pink,gray}.svg`
and their `-active.svg` variants are unchanged 64 × 64 Figma swatch exports.
The normal states come from `1902:3670` (orange from `1902:4049`); active
states come from `1902:4003`, `1902:4051`, `1902:4358`, `1902:4669`,
`1902:4977`, `1902:5284`, `1902:5591`, `1902:6203` and `1902:6510`.
Their source values are #D37918, #E15032, #C49E23, #19A234, #18AAD3,
#185DD3, #8E42FF, #F052B3 and #AFAFAF, respectively.

`settings-keyedit.svg` is the unchanged 24 × 24 pencil from Keyboard Shortcuts
frame `2437:14832`, icon instance `6338:14147` (`I6338:14147;2437:14889`).

`settings-general.svg` is the unchanged 24 × 24 sliders icon from the inactive
General row `3062:12563` in Playback settings frame `3062:12552`, matching the
active General icon in `3046:9282`.

- `settings-crop-link.svg`: original Figma Crop component `543:990`, sync-link instance `I774:1081;177:88;774:1039` (asset `bfdd0.svg`, exported through the official Figma MCP context on2026-10-13). Drives the existing top/bottom and left/right crop synchronization choices; no new crop behavior.
