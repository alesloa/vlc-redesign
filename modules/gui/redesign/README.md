# VLC GUI redesign

The visual source is the owner's [VLC Redesign Figma project](https://www.figma.com/design/NbLN6ylrDsmWVVTS8Jo10z/VLC-Redesign--Community-?node-id=0-1), together with the owner-supplied transcript of the [design walkthrough](https://www.youtube.com/watch?v=ERFeOgqk324). Interface labels and settings help come from those designs or VLC's existing translated strings and configuration metadata. Media titles, durations, tracks, devices, folders, playlists, chapters and bookmarks come from VLC's existing models; example content in Figma is not application data.

The [implementation audit](IMPLEMENTATION.md) records the implemented GUI scope, actual behavior checks and platform-validation limits. The [build and review notes](BUILD.md) explain the platform environments, isolated GUI checks and review packages. Features requiring a new decoding or core data interface are identified separately in the audit.

## Platform ownership

Windows and Linux use the existing Qt interface. macOS uses the existing native AppKit interface. Both interfaces retain VLC's playback, playlist, configuration and dialog APIs. The macOS Qt dummy compositor is suitable for offscreen interface checks and does not embed decoded video; use the native interface for playback on macOS.

| Area | Qt implementation | Native macOS implementation |
| --- | --- | --- |
| Palette and typography | `SystemPalette`, `VLCStyle`, shared QWidget theme, bundled Inter | Dynamic `NSColor` additions, shared view styling, bundled Inter |
| Player | Compact left playback controls, thick seek bar, cone volume, top actions, queue | Main and classic video views, shared controls and slider cells |
| Player settings | Playback, Video, Audio and Subtitles tabs using existing controller and configuration models | Four-tab popover using existing player and menu actions |
| Library, queue and navigation | Source-backed full/compact Home, real collection routes, ordered pins, music categories and bookmark/chapter panes | Source-backed full/compact Home, real collection grid/routes, ordered pins and independent Queue/bookmark panes |
| Global settings | Thirteen design categories, search, source help, existing Simple/All/Expert and save/reset paths | Thirteen design categories around the existing preference controls and save/reset paths |
| Menus and hotkeys | Promoted existing actions, real toolbar profiles, dedicated existing hotkey editor | Existing native menus and hotkey editor |
| Onboarding | Welcome, folder, theme/accent and actual configured shortcuts; existing consent steps retained | Welcome, folder chooser, native theme/accent and actual configured shortcuts |
| Secondary dialogs | Open media, network URL, effects, bookmarks, extensions and toolbar editor | Source-backed playlist/network dialogs, effects cards, modal shells and player gallery/preview editor |

The source exports and their individual Figma nodes are documented in [icons/README.md](icons/README.md). SVG source bytes and geometry remain unchanged; tint and mirroring occur during rendering. Font provenance and license are in [fonts/README.md](fonts/README.md).

The QWidget checkbox reuses VLC's existing `modules/gui/qt/pixmaps/icons/check.svg` through the `checkbox-check.svg` resource alias. Its checked, unchecked and disabled colors use the shared design palette.

## Behavior boundary

The redesign reorganizes existing GUI controls. It does not add decoding, networking, subtitle matching or media database behavior. Existing toolbar profiles and user shortcuts remain supported. Configuration-backed player options stage edits through Apply and Cancel, and unavailable plugin options are omitted or disabled.

The walkthrough also proposes subtitle cue timelines, seek waveforms, automatic subtitle matching, per-show setting presets and a sleep timer. Capability checks are recorded in the audit. Seek previews use VLC's existing thumbnail preparser, and the GUI sleep timer invokes the existing Stop action. Manual subtitle attachment uses existing stored external-media-file associations and the existing input slave API. Existing subtitle synchronization, filters, speed, tracks and bookmark/chapter APIs remain available.

## Validation

The integrated Qt GUI has been compiled and linked with Meson, including generated MOC, resource and UI files. The native GUI has been compiled and linked against VLC with all Objective-C sources and XIB resources. Native playback checks use the owner's supplied video. Qt runtime checks use the offscreen software backend, actual dialogs and models, and temporary data directories.

Actual Qt checks covered all thirteen settings categories, source help, search, Simple/All/Expert, header Close, application/video menus and all six onboarding pages. Player checks covered real library category and folder models, keyboard playback, bookmark Add/Select/Remove, the four tabs, wide and compact popup bounds, metadata-backed option staging/Cancel and isolated Apply followed by restoration. Both observers exited normally with no QML import, binding or layout warnings. A focused C++ check also exercises model/settings destruction during a modal recovery prompt and the normal Yes/No paths.

Native visual checks verified Light/Dark selected rows, readable preference labels and the time overlay with visible, hidden and fullscreen controls. Native GUI fixes also cover early video-window creation, single context-menu event handling, preference capability checks, resume time units/timer cleanup and responsive video remount constraints.

The owner's external file-drop regression was reproduced with a real Finder mouse drag. Restoring the redesigned library's registered drop target and a window fallback now forwards that same gesture to VLC's original open handler and starts the actual video. File parsing, autoplay preferences and specialized Queue insertion remain on their existing paths.

The owner's hover regression came from switching the video constraints when controls appeared. The native player now keeps one fixed video rectangle between the header and controls area while those controls fade. This leaves permanent black safe areas for the original time display and subtitles without changing VLC's OSD renderer or playback behavior. Direct show/hide checks compare the actual window, video view and sample-buffer layer geometry; they are not physical-mouse hover checks.

The owner's sidebar screenshot showed that macOS 26's native glass supplied left/bottom spacing while the navigation panel filled the top/right edges. A black perimeter host adds the existing eight-point spacing at those two edges and clips the original panel inside it. The split width, navigation actions and appearance colors are retained; older macOS sidebar hierarchies are unchanged.

The actual final Home window passes seven mounted-view, clipping, traffic-light and capture checks with normal Quit. Its new top/right interior gutters use the existing dark background color. Native outer window/glass borders retain their system rendering and are not claimed to be pixel-identical to the interior gutters.

New Qt checks also verified actual decoded seek frames, cache/cancellation and object destruction, hover timestamps and unchanged paused playback position. Inline filters read unsaved live Effects values, stage changes, apply only their section and restore on Cancel. Actual stored subtitle associations convert once to non-forced subtitle input slaves. The dedicated toolbar editor passed real drag/drop, Save/reopen and Cancel, using its original profile model.

For an isolated GUI check, use VLC's existing `VLC_USERDATA_PATH` environment variable for the media database and an explicit temporary `--config` file. `CFFIXED_USER_HOME` and XDG variables alone do not isolate the macOS media database. Back up and exactly restore both native and Qt GUI settings domains when checking profile Save or theme changes, as described in the build notes.

The final Qt source compiles on macOS, Linux ARM64 and Windows x64. The Linux staged package passed actual X11 video, video context menu, three playback/Home transitions and normal Quit without QML errors. The final Windows package loads its GUI, media library and 601 modules under Wine and quits normally; Wine does not validate native Windows Direct Composition. Native macOS passed all twelve onboarding layouts, the library and toolbar checks, and the final 28-check playlist/bookmark workflow with zero failures or constraint warnings and normal Quit. Both original GUI settings dictionaries were restored exactly.

Review artifacts are staged outside the source tree at `/Volumes/Code/Builds/vlc-redesign`: the native ARM64 app, Windows x64 ZIP, Ubuntu 26.04 ARM64 directory/archive, source patch/new-file archive and named validation evidence. These are review builds; the native app is ad-hoc signed, and native Windows GPU validation remains outstanding.
