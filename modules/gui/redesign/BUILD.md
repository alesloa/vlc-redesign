# Build and review the GUI redesign

The build inputs are the repository at `1176b56bdef7b96c9d6518b62be37ec8c32d92ed`, its existing build instructions and matching VideoLAN contributions. The redesign changes `modules/gui` and native resource packaging in `extras/package/macosx/package.mak`. Playback and other core sources remain unchanged.

## Existing review environments

| Target | Build used for validation | Runtime check |
| --- | --- | --- |
| macOS native | Separate AppKit plugin and app bundle built from the existing native sources and XIBs | Actual owner-supplied H.264/AAC video; window, context menu, fullscreen, controls and preferences |
| Qt on macOS | Meson build at `/tmp/vlc-redesign-build` | Offscreen software GUI observers with actual VLC models; use AppKit for macOS video playback |
| Linux ARM64 | Ubuntu 26.04 container `vlc-redesign-linux`, source `/work/source`, Meson build `/work/build` | Xvfb/Openbox, X11 and Mesa software rendering, actual owner video |
| Windows x64 | Official VideoLAN win64 CI image `20260611225331`, matching contrib, source `/work/source`, Automake build `win64` | Wine GUI loading, media library and normal Quit; native Windows compositor validation remains separate |

These paths identify the environments used for the audit. They are not prerequisites for a normal VLC build. Use the platform's existing VLC build instructions when building elsewhere.

Both Qt build systems register the new C++/QML models, Inter fonts and original design assets. When copying a source snapshot into an existing Meson build, explicitly reconfigure that build before compiling; preserved source timestamps can otherwise leave its generated source list stale. Linux validation enables fontconfig so the existing subtitle/OSD renderer can discover installed fonts.

## Preserve standard subtitle support

Source: the existing Matroska, libass, subsdec and FreeType targets in `modules/{demux,codec,text_renderer}/meson.build`, and the owner's embedded-subtitle regression. A review build using `-Dauto_features=disabled` must explicitly enable the normal subtitle stack; leaving its features `auto` disables them. Missing Matroska support makes this MKV fall back to avformat, which identifies its embedded SubRip tracks as an unknown codec in this source snapshot.

With the existing build dependencies installed, retain the original build options and explicitly enable:

```sh
meson configure <build-dir> -Dmatroska=enabled -Dlibass=enabled -Dfreetype=enabled -Dfribidi=enabled -Dharfbuzz=enabled
meson compile -C <build-dir> mkv_plugin libass_plugin freetype_plugin
python3 modules/gui/redesign/check-subtitle-package.py <package-dir> --meson-build <build-dir>
```

Use the target names returned by `meson introspect --targets` if the local Meson version spells them differently. For Linux, also enable `fontconfig` and include its system runtime dependencies. The native repair uses the repository's checksum-verified libebml 1.4.6 and libmatroska 1.7.2 as static PIC libraries, and bundles the exact libass/shaping dependency closure. Only existing plugins are rebuilt; the delivered core bytes and GUI code are preserved. The checker rejects missing plugins or disabled subtitle features, but runtime selection and actual caption rendering remain required.

## Isolate GUI interaction checks

Use an explicit temporary `--config` and `VLC_USERDATA_PATH` for test configuration and the media database. Windows paths must be Windows paths, including under Wine. On macOS, `CFFIXED_USER_HOME` alone does not isolate the Qt settings domain `com.vlc.vlc-qt-interface`.

Before a native or Qt observer saves profiles, layouts, pins or themes, export both `org.videolan.vlc` and `com.vlc.vlc-qt-interface`. Restore each by deleting the test domain and then importing its export; `defaults import` merges keys and by itself does not restore an exact snapshot. Export once more in a fresh process and compare the parsed plist dictionaries. If a domain was absent before testing, remove the test-created domain. All tests sharing these stores run sequentially.

Quit through the application's existing Quit action or RC `quit` command. Keep each native review app's resources and plugin frozen while it is running; package the next source snapshot into a separate app before replacing the preview.

## Native macOS review package

The native ARM64 app compiles 245 Objective-C sources and includes 49 compiled XIBs with the original GUI resource names. Its separate delivery copy bundles the exact 67 installed library dependencies used by that build. Only Mach-O load paths and signatures are changed during dependency packaging; VLC core and codec source remain unchanged.

The static package audit checks all 384 Mach-O images and 1,010 load commands. Each non-system dependency resolves inside the bundle; no Homebrew load path remains. The copied libraries and app pass strict ad-hoc signature checks. Runtime checks use that same frozen delivery copy, temporary VLC configuration/media data and exact restoration of both GUI preference domains.

This is an ARM64 review build tested on the owner's Mac, not a notarized public installer or an Intel Mac build. The dependency manifest and runtime evidence accompany the review artifacts.

## Windows package dependency check

The existing `make package-win-strip` target produces the normal Windows directory package. In this CI/contrib combination, the SRT input/output, x265 and GME plugins initially imported `libgcc_s_seh-1.dll`. VLC's existing Windows module loader searches system DLL locations, so copying this runtime beside the application did not resolve these imports.

The validation package relinks only those four existing plugin targets with their generated `SRT_LIBS`, `LIBS_x265` and `LIBS_gme` make variables, replacing the explicit `-lgcc_s` entry with `-lgcc_eh`. This is a build-artifact adjustment; it changes no core or codec source and retains the original contributed libraries. Install and strip the resulting plugin DLLs in the normal package, then inspect PE imports with `x86_64-w64-mingw32-objdump -p`. Confirm that all packaged plugins are free of unresolved GCC/pthread runtime imports before running the package.

The checked package subsequently loaded all four plugins, the Qt GUI and the actual media library under Wine without QML import errors and exited normally. Wine's unimplemented Direct Composition device limits the rendering check; a Wine smoke test does not establish native Windows compositor correctness.

## Linux review package

The ARM64 runtime stage uses `meson install --no-rebuild --tags runtime`. Include the original built `vlc-qt-check` helper alongside `vlc-preparser` and `vlc-cache-gen`. The portable launcher sets `VLC_PLUGIN_PATH`, `VLC_LIBEXEC_PATH` and both the architecture library directory and its `vlc` subdirectory in `LD_LIBRARY_PATH`; the XCB video plugins use the latter for `libvlc_xcb_events.so`.

This is an Ubuntu 26.04 ARM64 review directory with system Qt 6.10, FFmpeg 8, fontconfig and X11/Wayland dependencies. It is not a self-contained AppImage or an x86_64 package. All 318 checked runtime ELF files resolve their dependencies in the review environment. The final staged binary passed actual video playback, a visible video context menu, three playback/Home transitions and normal Quit with zero QML errors.

For an X11 capture, select the application's managed client from `_NET_CLIENT_LIST` using its `_NET_WM_PID`. Qt also creates unmapped backing windows with VLC titles; resizing one of those does not resize the visible player. Keep screenshot filenames unique when comparing successive captures.

The [implementation audit](IMPLEMENTATION.md) records the current source snapshot's behavior checks and validation limits. Review archives, source changes and named evidence are staged at `/Volumes/Code/Builds/vlc-redesign`; no production deployment or public installer publication is implied.
