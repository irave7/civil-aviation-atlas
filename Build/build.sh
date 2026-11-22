#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${ATLAS_BUILD_DIR:-$project_root/Build/.products}"
archive="$build_dir/AirportAtlas.xcarchive"
signed_archive="$build_dir/AirportAtlas-Signed.xcarchive"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

mkdir -p "$build_dir"
xcode_args=(-project "$project_root/AirportAtlas.xcodeproj" -scheme AirportAtlas)

case "${1:-}" in
    simulator)
        xcodebuild "${xcode_args[@]}" -configuration Debug -destination 'generic/platform=iOS Simulator' \
            -derivedDataPath "$build_dir/simulator" CODE_SIGNING_ALLOWED=NO build
        ;;
    device)
        xcodebuild "${xcode_args[@]}" -configuration Release -destination 'generic/platform=iOS' \
            -derivedDataPath "$build_dir/device" CODE_SIGNING_ALLOWED=NO build
        ;;
    test)
        simulator_id="${2:?Pass the UUID of an available iPhone or iPad simulator as the second argument.}"
        test_result="$build_dir/airport-atlas-tests-$(date +%Y%m%d-%H%M%S).xcresult"
        xcodebuild "${xcode_args[@]}" -destination "platform=iOS Simulator,id=$simulator_id" \
            -derivedDataPath "$build_dir/simulator" -resultBundlePath "$test_result" \
            -parallel-testing-enabled NO test
        ;;
    archive)
        xcodebuild "${xcode_args[@]}" -configuration Release -destination 'generic/platform=iOS' \
            -derivedDataPath "$build_dir/device" -archivePath "$archive" \
            CODE_SIGNING_ALLOWED=NO archive
        ;;
    archive-signed)
        developer_team="${ATLAS_DEVELOPMENT_TEAM:?Set ATLAS_DEVELOPMENT_TEAM to the authorized Apple Developer team ID.}"
        xcodebuild "${xcode_args[@]}" -configuration Release -destination 'generic/platform=iOS' \
            -derivedDataPath "$build_dir/device" -archivePath "$signed_archive" \
            -allowProvisioningUpdates "DEVELOPMENT_TEAM=$developer_team" archive
        ;;
    mainland-device|mainland-archive-signed)
        python3 "$project_root/Build/prepare-mainland-catalog.py" --check
        mainland_args=(-project "$project_root/AirportAtlas.xcodeproj" -scheme AirportAtlasMainlandReview
            -destination 'generic/platform=iOS' -derivedDataPath "$build_dir/mainland-device")
        if [[ "$1" == mainland-device ]]; then
            xcodebuild "${mainland_args[@]}" CODE_SIGNING_ALLOWED=NO build
        else
            developer_team="${ATLAS_DEVELOPMENT_TEAM:?Set ATLAS_DEVELOPMENT_TEAM to the authorized Apple Developer team ID.}"
            xcodebuild "${mainland_args[@]}" -archivePath "$build_dir/AirportAtlas-MainlandReview.xcarchive" \
                -allowProvisioningUpdates "DEVELOPMENT_TEAM=$developer_team" archive
        fi
        ;;
    export-testflight|upload-testflight|upload-testflight-internal)
        developer_team="${ATLAS_DEVELOPMENT_TEAM:?Set ATLAS_DEVELOPMENT_TEAM to the authorized Apple Developer team ID.}"
        if [[ ! -d "$signed_archive" ]]; then
            printf 'Create the signed archive before distributing the App Store package.\n' >&2
            exit 2
        fi
        destination=export
        output="$build_dir/testflight"
        options="$build_dir/ExportOptions.plist"
        internal_only=false
        if [[ "$1" == upload-testflight* ]]; then
            destination=upload
            output="$build_dir/testflight-upload"
            options="$build_dir/UploadOptions.plist"
        fi
        if [[ "$1" == upload-testflight-internal ]]; then
            internal_only=true
        fi
        /usr/bin/plutil -create xml1 "$options"
        /usr/bin/plutil -insert method -string app-store-connect "$options"
        /usr/bin/plutil -insert destination -string "$destination" "$options"
        /usr/bin/plutil -insert signingStyle -string automatic "$options"
        /usr/bin/plutil -insert teamID -string "$developer_team" "$options"
        /usr/bin/plutil -insert manageAppVersionAndBuildNumber -bool false "$options"
        /usr/bin/plutil -insert testFlightInternalTestingOnly -bool "$internal_only" "$options"
        xcodebuild -exportArchive -archivePath "$signed_archive" -exportPath "$output" \
            -exportOptionsPlist "$options" -allowProvisioningUpdates
        ;;
    *)
        printf 'Usage: %s {simulator|device|test SIMULATOR_UUID|archive|archive-signed|mainland-device|mainland-archive-signed|export-testflight|upload-testflight|upload-testflight-internal}\n' "$0" >&2
        exit 2
        ;;
esac
