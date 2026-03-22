#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
codesign_identity="-"
notarize=""
apple_id=""
team_id=""
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        --notarize) notarize=1; shift;;
        --apple-id) apple_id="$2"; shift 2;;
        --team-id) team_id="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

./build-release.sh --build-version "$build_version" --codesign-identity "$codesign_identity"

dmg_name="Zuo-v$build_version"
dmg_path=".release/$dmg_name.dmg"
dmg_staging=".release/dmg-staging"

rm -rf "$dmg_staging"
mkdir -p "$dmg_staging"
cp -r ".release/Zuo-v$build_version/Zuo.app" "$dmg_staging/"
ln -s /Applications "$dmg_staging/Applications"

hdiutil create \
    -volname "$dmg_name" \
    -srcfolder "$dmg_staging" \
    -ov \
    -format UDZO \
    "$dmg_path"

rm -rf "$dmg_staging"

######################
### NOTARIZE + STAPLE
######################

if test -n "$notarize"; then
    if test -z "$apple_id" || test -z "$team_id"; then
        echo "Error: --notarize requires --apple-id and --team-id" > /dev/stderr
        exit 1
    fi

    echo ""
    echo "=== Notarizing DMG ==="
    echo "  Submitting to Apple (this may take a few minutes)..."

    xcrun notarytool submit "$dmg_path" \
        --apple-id "$apple_id" \
        --team-id "$team_id" \
        --keychain-profile "notarytool-profile" \
        --wait

    echo "  Stapling notarization ticket..."
    xcrun stapler staple "$dmg_path"
    xcrun stapler validate "$dmg_path"
fi

echo ""
echo "=== DMG created ==="
echo "  $dmg_path"
