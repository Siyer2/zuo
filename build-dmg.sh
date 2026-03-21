#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
codesign_identity="-"
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

./build-release.sh --build-version "$build_version" --codesign-identity "$codesign_identity"

dmg_name="Zuo-v$build_version"
dmg_path=".release/$dmg_name.dmg"
dmg_staging=".release/dmg-staging"

rm -rf "$dmg_staging"
mkdir -p "$dmg_staging"
cp -r ".release/AeroSpace-v$build_version/AeroSpace.app" "$dmg_staging/"
ln -s /Applications "$dmg_staging/Applications"

hdiutil create \
    -volname "$dmg_name" \
    -srcfolder "$dmg_staging" \
    -ov \
    -format UDZO \
    "$dmg_path"

rm -rf "$dmg_staging"

echo ""
echo "=== DMG created ==="
echo "  $dmg_path"
