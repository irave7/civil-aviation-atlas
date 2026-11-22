#!/bin/bash
set -euo pipefail

artifact="${1:?Pass an iPad .app, .xcarchive, or .ipa.}"
require_signing="${2:-}"
build_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

case "$artifact" in
    *.app)
        app="$artifact"
        ;;
    *.xcarchive)
        app="$artifact/Products/Applications/AirportAtlas.app"
        ;;
    *.ipa)
        mkdir -p "$build_root/.products"
        expanded="$(mktemp -d "$build_root/.products/ipa-verification.XXXXXX")"
        trap 'rm -rf "$expanded"' EXIT
        /usr/bin/unzip -tq "$artifact"
        /usr/bin/unzip -q "$artifact" -d "$expanded"
        app="$expanded/Payload/AirportAtlas.app"
        # File Provider can add Finder metadata to the extracted app while it is in Documents.
        /usr/bin/xattr -d com.apple.FinderInfo "$app" 2>/dev/null || true
        ;;
    *)
        printf 'Expected an iPad .app, .xcarchive, or .ipa.\n' >&2
        exit 2
        ;;
esac

if [[ "$require_signing" == --require-signed ]]; then
    /usr/bin/codesign --verify --deep --strict "$app"
    test -f "$app/embedded.mobileprovision"
    printf 'Verified signature and embedded provisioning profile.\n'
fi

python3 - "$app" "$build_root" <<'PY'
import plistlib
import sys
from pathlib import Path

app = Path(sys.argv[1])
project = Path(sys.argv[2]).parent
with (app / "Info.plist").open("rb") as info:
    settings = plistlib.load(info)
assert settings["UIDeviceFamily"] == [2], "Expected native iPad only"
assert settings["MinimumOSVersion"] == "26.0", "Incorrect minimum OS"
assert settings["CFBundleSupportedPlatforms"] == ["iPhoneOS"], "Expected an iPad device build"
assert settings["CFBundleExecutable"] == "AirportAtlas", "Unexpected executable name"
assert settings.get("CFBundleDisplayName"), "Missing iPad display name"
assert settings["ITSAppUsesNonExemptEncryption"] is False, "Incorrect export compliance setting"
assert (app / "Assets.car").is_file(), "Missing compiled app icon catalog"
resources = project / "App" / "Resources"
for filename in ("airport-data.json", "observed-routes.json", "airport-site-layouts.json", "airport-building-layouts.json", "airport-runway-supplements.json",
                 "airport-site-terrain.json", "HKG-T1-Exterior.usdz", "HKGPhotoExterior.jpg", "HKGPhotoInterior.jpg",
                 "AtlasFallbackChinese.otf", "AtlasFallbackChinese-LICENSE.txt"):
    assert (app / filename).read_bytes() == (resources / filename).read_bytes(), (
        f"Missing or mismatched bundled resource: {filename}"
    )
print(f"Verified iPadOS {settings['MinimumOSVersion']} device bundle, version "
      f"{settings['CFBundleShortVersionString']} ({settings['CFBundleVersion']})")
PY

xcrun lipo -verify_arch arm64 "$app/AirportAtlas"
xcrun vtool -arch arm64 -show-build "$app/AirportAtlas" | awk '$1 == "platform" && $2 == "IOS" { found = 1 } END { exit !found }'
printf 'Verified native iOS ARM64 executable.\n'
