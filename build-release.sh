#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
codesign_identity="zuo-codesign-certificate"
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

#############
### BUILD ###
#############

./build-docs.sh
./build-shell-completion.sh

./generate.sh
./script/check-uncommitted-files.sh
./generate.sh --build-version "$build_version" --codesign-identity "$codesign_identity" --generate-git-hash

swift build -c release --arch arm64 --arch x86_64 --product zuo -Xswiftc -warnings-as-errors # CLI

rm -rf .release && mkdir .release

xcode_configuration="Release"
xcodebuild -version
xcodebuild-pretty .release/xcodebuild.log clean build \
    -scheme Zuo \
    -destination "generic/platform=macOS" \
    -configuration "$xcode_configuration" \
    -derivedDataPath .xcode-build

git checkout .

cp -r ".xcode-build/Build/Products/$xcode_configuration/Zuo.app" .release
cp -r .build/apple/Products/Release/zuo .release

################
### SIGN CLI ###
################

codesign -s "$codesign_identity" --options runtime --timestamp .release/zuo

################
### VALIDATE ###
################

expected_layout=$(cat <<EOF
.release/Zuo.app
.release/Zuo.app/Contents
.release/Zuo.app/Contents/_CodeSignature
.release/Zuo.app/Contents/_CodeSignature/CodeResources
.release/Zuo.app/Contents/MacOS
.release/Zuo.app/Contents/MacOS/Zuo
.release/Zuo.app/Contents/Resources
.release/Zuo.app/Contents/Resources/default-config.toml
.release/Zuo.app/Contents/Resources/AppIcon.icns
.release/Zuo.app/Contents/Resources/Assets.car
.release/Zuo.app/Contents/Info.plist
.release/Zuo.app/Contents/PkgInfo
EOF
)

if test "$expected_layout" != "$(find .release/Zuo.app)"; then
    echo "!!! Expect/Actual layout don't match !!!"
    find .release/Zuo.app
    exit 1
fi

check-universal-binary() {
    if ! file "$1" | grep --fixed-string -q "Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64"; then
        echo "$1 is not a universal binary"
        exit 1
    fi
}

check-contains-hash() {
    hash=$(git rev-parse HEAD)
    if ! strings "$1" | grep --fixed-string "$hash" > /dev/null; then
        echo "$1 doesn't contain $hash"
        exit 1
    fi
}

check-universal-binary .release/Zuo.app/Contents/MacOS/Zuo
check-universal-binary .release/zuo

check-contains-hash .release/Zuo.app/Contents/MacOS/Zuo
check-contains-hash .release/zuo

codesign -v .release/Zuo.app
codesign -v .release/zuo

############
### PACK ###
############

mkdir -p ".release/Zuo-v$build_version/manpage" && cp .man/*.1 ".release/Zuo-v$build_version/manpage"
cp -r ./legal ".release/Zuo-v$build_version/legal"
cp -r .shell-completion ".release/Zuo-v$build_version/shell-completion"
cd .release
    mkdir -p "Zuo-v$build_version/bin" && cp -r zuo "Zuo-v$build_version/bin"
    cp -r Zuo.app "Zuo-v$build_version"
    zip -r "Zuo-v$build_version.zip" "Zuo-v$build_version"
cd -

#################
### Brew Cask ###
#################
for cask_name in zuo zuo-dev; do
    ./script/build-brew-cask.sh \
        --cask-name "$cask_name" \
        --zip-uri ".release/Zuo-v$build_version.zip" \
        --build-version "$build_version"
done
