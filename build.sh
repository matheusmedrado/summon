#!/bin/bash
# ./build.sh           build build/Summon.app (universal: Apple silicon + Intel)
# ./build.sh install   build, copy to /Applications and launch
# ./build.sh dmg       build and package build/Summon-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP=build/Summon.app
LABEL=com.matheusmedrado.summon

build_arch() {
    swift build -c release --triple "$1-apple-macosx14.0" >&2
    echo "$(swift build -c release --triple "$1-apple-macosx14.0" --show-bin-path)/Summon"
}

ARM=$(build_arch arm64)
INTEL=$(build_arch x86_64)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
lipo -create "$ARM" "$INTEL" -output "$APP/Contents/MacOS/Summon"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/Mascot.png Resources/MenuIcon.png Resources/MenuIcon@2x.png "$APP/Contents/Resources/"
cp "Resources/$LABEL.plist" "$APP/Contents/Library/LaunchAgents/"

# Sign with a local "Summon Local Signing" certificate when there is one, so
# macOS keeps the Accessibility permission across updates. Without it
# (ad-hoc), every build counts as a new app and needs granting again.
IDENTITY=$(security find-certificate -c "Summon Local Signing" -Z 2>/dev/null | awk '/SHA-1/{print $NF}')
codesign --force --sign "${IDENTITY:--}" --identifier "$LABEL" "$APP" >/dev/null
echo "Built $APP ($VERSION)"

case "${1:-}" in
install)
    # Stop the running copy. Older builds were started by a hand-written
    # agent in ~/Library/LaunchAgents; the app now registers its own.
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
    pkill -x Summon 2>/dev/null || true
    sleep 0.5
    rm -rf /Applications/Summon.app
    cp -R "$APP" /Applications/
    open /Applications/Summon.app
    echo "Installed /Applications/Summon.app"
    ;;
dmg)
    DMG="build/Summon-$VERSION.dmg"
    STAGE=$(mktemp -d)
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    rm -f "$DMG"
    hdiutil create -volname "Summon" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
    echo "Packaged $DMG"
    shasum -a 256 "$DMG"
    ;;
esac
