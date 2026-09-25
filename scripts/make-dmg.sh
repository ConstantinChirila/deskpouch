#!/bin/zsh
# Builds the Release app and packs it into build/Deskpouch-<version>.dmg (the app plus an Applications shortcut).
# Used by .github/workflows/dmg.yml and runnable by hand.
#
#   VERSION=1.2.0 BUILD=45 scripts/make-dmg.sh
#
# VERSION defaults to MARKETING_VERSION in project.yml, BUILD to 1.
# Signing: ad-hoc unless SIGN_IDENTITY (a "Developer ID Application: …" name or hash in the keychain) and TEAM_ID
# are set. An ad-hoc build opens only after System Settings › Privacy & Security › Open Anyway, and macOS forgets
# its Accessibility, Microphone and Screen Recording grants with every new build. A signed build is notarized and
# stapled too (the app first, then the DMG), with NOTARY_PROFILE (a `notarytool store-credentials` profile, for a
# desk) or NOTARY_APPLE_ID and NOTARY_PASSWORD (an app-specific password, for CI). A signed build without notary
# credentials is an error, unless ALLOW_UNNOTARIZED=1 says it is meant.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -d Deskpouch.xcodeproj || project.yml -nt Deskpouch.xcodeproj/project.pbxproj ]]; then
  xcodegen generate
fi

# No get-task-allow: Xcode adds it to a plain `build`, notarization refuses it, and with it any process of the same
# user can attach to Deskpouch and borrow its grants.
settings=("CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO")
[[ -n "${VERSION:-}" ]] && settings+=("MARKETING_VERSION=$VERSION")
[[ -n "${BUILD:-}" ]] && settings+=("CURRENT_PROJECT_VERSION=$BUILD")
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  : "${TEAM_ID:?TEAM_ID is needed with SIGN_IDENTITY}"
  # --timestamp: notarization refuses signatures without a secure timestamp.
  settings+=("CODE_SIGN_IDENTITY=$SIGN_IDENTITY" "DEVELOPMENT_TEAM=$TEAM_ID" "OTHER_CODE_SIGN_FLAGS=--timestamp")
  notary=()
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notary=(--keychain-profile "$NOTARY_PROFILE")
  elif [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
    notary=(--apple-id "$NOTARY_APPLE_ID" --team-id "$TEAM_ID" --password "$NOTARY_PASSWORD")
  elif [[ "${ALLOW_UNNOTARIZED:-}" != 1 ]]; then
    echo "SIGN_IDENTITY is set but there are no notary credentials (ALLOW_UNNOTARIZED=1 to build anyway)" >&2
    exit 1
  fi
else
  # Not the machine's dev certificate from Signing.local.xcconfig: nobody else has it.
  settings+=("CODE_SIGN_IDENTITY=-")
fi

derived=build/DerivedData-release
# The build (and every package plugin and script in it) does not get to see the notary credentials.
env -u NOTARY_APPLE_ID -u NOTARY_PASSWORD -u NOTARY_PROFILE xcodebuild -scheme Deskpouch -configuration Release -derivedDataPath "$derived" \
  -skipPackagePluginValidation "${settings[@]}" build | { grep -E "error:|warning: |BUILD" || true; }

app="$derived/Build/Products/Release/Deskpouch.app"
codesign --verify --deep --strict "$app"
if codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q get-task-allow; then
  echo "get-task-allow is in the signature" >&2
  exit 1
fi
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

# The app gets its own ticket: stapled, it passes Gatekeeper offline once copied out of the DMG.
if [[ -n "${SIGN_IDENTITY:-}" ]] && (( ${#notary} )); then
  ditto -c -k --keepParent "$app" "$staging/Deskpouch.zip"
  xcrun notarytool submit "$staging/Deskpouch.zip" "${notary[@]}" --wait
  rm "$staging/Deskpouch.zip"
  xcrun stapler staple "$app"
fi
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

dmg="build/Deskpouch-$version.dmg"
rm -f "$dmg"
hdiutil create -volname "Deskpouch $version" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --sign "$SIGN_IDENTITY" --timestamp "$dmg"
  if (( ${#notary} )); then
    xcrun notarytool submit "$dmg" "${notary[@]}" --wait
    xcrun stapler staple "$dmg"
    spctl --assess --type open --context context:primary-signature "$dmg"
  fi
fi

echo "$dmg"
