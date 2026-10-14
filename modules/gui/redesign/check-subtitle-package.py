#!/usr/bin/env python3
"""Check standard subtitle plugins and optional Meson feature configuration.

Plugin names come from modules/{demux,codec,text_renderer}/meson.build.
This static check does not replace subtitle decoding/rendering validation.
"""

import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--meson-build", type=Path)
    args = parser.parse_args()
    package = args.package.resolve(strict=True)
    if not package.is_dir():
        parser.error("package must be a directory")

    if (package / "Contents/Info.plist").is_file():
        suffix = ".dylib"
    elif (package / "vlc.exe").is_file():
        suffix = ".dll"
    else:
        suffix = ".so"
    plugins = {}
    missing = []
    for name in ("mkv", "libass", "subsdec", "freetype"):
        filename = f"lib{name}_plugin{suffix}"
        matches = sorted(path for path in package.rglob(filename) if path.is_file() and path.stat().st_size)
        plugins[name] = [str(path.relative_to(package)) for path in matches]
        if not matches:
            missing.append(filename)

    features = {}
    disabled = []
    configuration_source = None
    if args.meson_build:
        configuration_source = args.meson_build / "meson-info/intro-buildoptions.json"
        options = {option["name"]: option["value"] for option in json.loads(configuration_source.read_text())}
        for name in ("matroska", "libass", "freetype", "fribidi", "harfbuzz"):
            value = options[name]
            features[name] = value
            if value == "disabled" or (value == "auto" and options["auto_features"] == "disabled"):
                disabled.append(name)

    print(json.dumps({
        "package": str(package),
        "plugin_source": "modules/{demux,codec,text_renderer}/meson.build",
        "plugins": plugins,
        "missing_plugins": missing,
        "configuration_source": str(configuration_source) if configuration_source else None,
        "features": features,
        "disabled_features": disabled,
        "passed": not missing and not disabled,
        "scope": "Static plugin presence and configured features; no runtime decoding proof.",
    }, indent=2))
    return int(bool(missing or disabled))


if __name__ == "__main__":
    raise SystemExit(main())
