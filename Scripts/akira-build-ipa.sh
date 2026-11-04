#!/usr/bin/env bash
# Akira Arcade: build an unsigned AkiraArcade.ipa for AltStore / SideStore and update
# altstore/source.json with its size, version and today's date.
#
#   Scripts/akira-build-ipa.sh            → build/AkiraArcade.ipa
#
# AltStore and SideStore sign the app with the user's own Apple ID when they install it,
# so the IPA is built without signing. Run it on a Mac with Xcode and the submodules
# checked out (see the README). Output also goes to build/akira-build-ipa.log.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build
exec > >(tee build/akira-build-ipa.log) 2>&1

ARCHIVE="build/AkiraArcade.xcarchive"
rm -rf "$ARCHIVE" build/Payload build/AkiraArcade.ipa

echo "akira: archiving (Release, unsigned)"
xcodebuild archive \
    -workspace Delta.xcworkspace \
    -scheme Delta \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    | grep -E "error:|warning: .*Akira|ARCHIVE (SUCCEEDED|FAILED)" || true

APP="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' | head -1)"
if [ -z "$APP" ]; then
    echo "akira: archive failed; see build/akira-build-ipa.log" >&2
    exit 1
fi

echo "akira: packing $APP"
mkdir -p build/Payload
cp -R "$APP" build/Payload/
(cd build && zip -qry AkiraArcade.ipa Payload)
rm -rf build/Payload

SIZE=$(stat -f%z build/AkiraArcade.ipa)
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Info.plist")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")

python3 - "$SIZE" "$VERSION" "$BUILD" "$BUNDLE_ID" <<'PY'
import json, sys, datetime
size, version, build, bundle_id = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
path = "altstore/source.json"
with open(path) as f:
    source = json.load(f)
app = source["apps"][0]
app["bundleIdentifier"] = bundle_id
latest = app["versions"][0]
latest.update(size=size, version=version, buildVersion=build, date=datetime.date.today().isoformat())
with open(path, "w") as f:
    json.dump(source, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

echo "akira: done: build/AkiraArcade.ipa ($SIZE bytes, $BUNDLE_ID $VERSION ($BUILD)); altstore/source.json updated"
