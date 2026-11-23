#!/bin/bash
set -euo pipefail

artifact="${1:?Pass an iOS .app, .xcarchive, or .ipa.}"
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
        expanded="$(mktemp -d "${TMPDIR:-/tmp}/airport-atlas-ipa.XXXXXX")"
        trap 'rm -rf "$expanded"' EXIT
        /usr/bin/unzip -tq "$artifact"
        /usr/bin/unzip -q "$artifact" -d "$expanded"
        app="$expanded/Payload/AirportAtlas.app"
        ;;
    *)
        printf 'Expected an iOS .app, .xcarchive, or .ipa.\n' >&2
        exit 2
        ;;
esac

if [[ "$require_signing" == --require-signed ]]; then
    /usr/bin/codesign --verify --deep --strict "$app"
    test -f "$app/embedded.mobileprovision"
    printf 'Verified signature and embedded provisioning profile.\n'
fi

python3 - "$app" "$build_root" <<'PY'
import json
import plistlib
import re
import sys
from pathlib import Path

app = Path(sys.argv[1])
project = Path(sys.argv[2]).parent
with (app / "Info.plist").open("rb") as info:
    settings = plistlib.load(info)
assert settings["UIDeviceFamily"] == [1, 2], "Expected native iPhone and iPad"
assert settings["MinimumOSVersion"] == "26.0", "Incorrect minimum OS"
assert settings["CFBundleSupportedPlatforms"] == ["iPhoneOS"], "Expected a native iOS device build"
assert settings["CFBundleExecutable"] == "AirportAtlas", "Unexpected executable name"
assert settings.get("CFBundleDisplayName"), "Missing app display name"
assert settings["ITSAppUsesNonExemptEncryption"] is False, "Incorrect export compliance setting"
assert (app / "Assets.car").is_file(), "Missing compiled app icon catalog"
orientations = {"UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"}
assert set(settings["UISupportedInterfaceOrientations~iphone"]) == orientations, "Unexpected iPhone orientations"
assert orientations <= set(settings["UISupportedInterfaceOrientations~ipad"]), "Unexpected iPad orientations"
assert "NSLocationWhenInUseUsageDescription" not in settings, "Unexpected location request"
assert "NSUserTrackingUsageDescription" not in settings, "Unexpected tracking request"
assert "NSAppTransportSecurity" not in settings, "Unexpected transport security exceptions"

resources = project / "App" / "Resources"
global_files = {
    "airport-data.json", "observed-routes.json", "airport-site-layouts.json",
    "airport-building-layouts.json", "airport-runway-supplements.json", "airport-site-terrain.json",
    "HKG-T1-Exterior.usdz", "HKGPhotoExterior.jpg", "HKGPhotoInterior.jpg",
}
mainland_files = {"airport-data-mainland.json", "observed-routes-mainland.json"}
common_files = {"AtlasFallbackChinese.otf", "AtlasFallbackChinese-LICENSE.txt", "PrivacyInfo.xcprivacy"}
icon = settings["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconName"]
assert icon in ("AppIcon", "MainlandAppIcon"), "Unexpected app icon"
mainland = icon == "MainlandAppIcon"
expected, excluded = (mainland_files, global_files) if mainland else (global_files, mainland_files)
for filename in expected | common_files:
    assert (app / filename).read_bytes() == (resources / filename).read_bytes(), f"Missing or mismatched resource: {filename}"
narration_files = {
    f"narration-{voice}-{cue}.m4a"
    for voice in ("captain", "guide", "story")
    for cue in ("departing", "cruise", "approach", "arrived", "rotate", "gearUp", "gearDown",
                "briefing", "taxiOut", "roll", "touchdown", "taxiIn")
}
flight_effects = {f"flight-{cue}.m4a" for cue in
                  ("cabin", "engine", "airflow", "roll", "chime", "switch", "touchdown", "gear", "reverse", "flaps")}
carrier_files = {
    f"carrier-{carrier}-{phase}.m4a"
    for carrier in ("air-china", "china-eastern", "china-southern", "xiamen-air",
                    "japan-airlines", "singapore-airlines", "emirates", "lufthansa")
    for phase in ("briefing", "departing", "approach", "arrived")
}
route_files = {
    f"route-{key}-{phase}-{variant}.m4a"
    for key in ("SHA", "PEK", "FOC", "PVG", "CAN", "TFU", "SIN", "HND", "JFK", "SFO",
                "PKX", "XMN", "SZX", "HKG", "NRT", "ICN", "LAX", "LHR", "DXB", "CN", "ASIA", "WORLD")
    for phase in ("departure", "arrival")
    for variant in (0, 1)
}
challenge_source = (project / "App" / "FlightChallenges.swift").read_text()
challenge_files = {f"challenge-{origin}-{destination}.m4a" for origin, destination in
                   re.findall(r'\.init\("([A-Z]{3})", "([A-Z]{3})"', challenge_source)}
assert len(challenge_files) >= 20, "The representative route audio list is incomplete"
observation_dir = resources / "ObservationVoices"
observations = json.loads((observation_dir / "observation-scripts.json").read_text())
observation_ids = {f"airport-{key}" for key in re.findall(r'\.init\(id: "([A-Z]{3})"', (project / "App/FlightAirportChapters.swift").read_text())}
observation_ids.update(f"aircraft-{key}" for key in re.findall(r'\.init\(id: "([^"]+)"', (project / "App/AtlasAircraftMissions.swift").read_text()))
assert set(observations) == observation_ids and all(observations.values()), "Observation transcripts do not match the missions"
observation_files = {"observation-scripts.json"} | {f"observation-{role}{key}.m4a" for key in observations for role in ("", "captain-", "story-")}
captions = json.loads((resources / "Narration/flight-transcripts.json").read_text())
assert {stem + ".m4a" for stem in captions} == narration_files | carrier_files | route_files | challenge_files, "Flight captions are incomplete"
for folder, files in (("Narration", narration_files | {"flight-transcripts.json"}), ("FlightEffects", flight_effects),
                      ("ObservationVoices", observation_files),
                      ("CarrierCabin", carrier_files), ("RouteVoices", route_files),
                      ("ChallengeVoices", challenge_files)):
    for filename in files:
        source = resources / folder / filename
        bundled = next((entry / filename for entry in (app, app / folder, app / "Resources" / folder)
                        if (entry / filename).is_file()), None)
        assert bundled and bundled.read_bytes() == source.read_bytes(), f"Missing or mismatched audio: {filename}"
for filename in excluded:
    assert not (app / filename).exists(), f"Unexpected distribution resource: {filename}"
manifest = plistlib.loads((app / "PrivacyInfo.xcprivacy").read_bytes())
assert manifest["NSPrivacyTracking"] is False
assert manifest["NSPrivacyCollectedDataTypes"] == []
assert manifest["NSPrivacyAccessedAPITypes"] == [{
    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
    "NSPrivacyAccessedAPITypeReasons": ["CA92.1"],
}]
print(f"Verified {'MainlandReview' if mainland else 'standard'} iPhone and iPad device bundle, "
      f"iOS minimum {settings['MinimumOSVersion']}, version {settings['CFBundleShortVersionString']} ({settings['CFBundleVersion']})")
PY

xcrun lipo -verify_arch arm64 "$app/AirportAtlas"
xcrun vtool -arch arm64 -show-build "$app/AirportAtlas" | awk '$1 == "platform" && $2 == "IOS" { found = 1 } END { exit !found }'
printf 'Verified native iOS ARM64 executable.\n'
