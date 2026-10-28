#!/usr/bin/env bash
# Builds the signed Release app for the tagged version and packs it into
# dist/JUMP.dmg. The name never changes so the website can link to
# releases/latest/download/JUMP.dmg; the volume name carries the version.
# With --upload it also attaches the .dmg to the GitHub release for that tag,
# creating the release if it does not exist, and points the Homebrew cask in
# alvaldes/homebrew-tap at it.
#
# Usage: scripts/release.sh [--upload]
#
# Needs Config/Signing.local.xcconfig: an ad-hoc signature changes on every
# build, so users would lose the Accessibility permission on each update.
set -euo pipefail

upload=false
case "${1:-}" in
  "") ;;
  --upload) upload=true ;;
  *) echo "usage: scripts/release.sh [--upload]" >&2; exit 64 ;;
esac

root="$(git rev-parse --show-toplevel)"
cd "$root"

version="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)"
tag="v$version"
[[ -n "$version" ]] || { echo "error: MARKETING_VERSION not found in project.yml" >&2; exit 1; }

# The .dmg must be exactly what the tag names.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: the working tree has changes; commit or stash them first" >&2; exit 1
fi
if [[ "$(git rev-parse -q --verify "refs/tags/$tag^{commit}" || true)" != "$(git rev-parse HEAD)" ]]; then
  echo "error: HEAD is not tagged $tag (the version in project.yml)" >&2; exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Building JUMP $version (Release)…"
xcodegen generate --quiet
xcodebuild -project JUMP.xcodeproj -scheme JUMP -configuration Release \
  -derivedDataPath "$work/build" build -quiet
app="$work/build/Build/Products/Release/JUMP.app"

codesign --verify --strict "$app"
authority="$(codesign -dvv "$app" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
if [[ -z "$authority" ]]; then
  echo "error: the app is ad-hoc signed; set up Config/Signing.local.xcconfig (see README)" >&2; exit 1
fi
built="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$built" == "$version" ]] || { echo "error: built version $built, expected $version" >&2; exit 1; }

echo "Packing the disk image…"
mkdir -p "$work/dmg" dist
cp -R "$app" "$work/dmg/"
ln -s /Applications "$work/dmg/Applications"
dmg="dist/JUMP.dmg"
hdiutil create -quiet -volname "JUMP $version" -srcfolder "$work/dmg" -ov -format UDZO "$dmg"
hdiutil verify -quiet "$dmg"

sha="$(shasum -a 256 "$dmg" | cut -d' ' -f1)"
echo "$dmg"
echo "  signed by: $authority"
echo "  sha256:    $sha"

if $upload; then
  if gh release view "$tag" >/dev/null 2>&1; then
    gh release upload "$tag" "$dmg" --clobber
  else
    # --verify-tag: the tag must already be pushed.
    gh release create "$tag" "$dmg" --title "JUMP $version" --generate-notes --verify-tag
  fi
  echo "Uploaded to release $tag."

  # The cask pins the .dmg's sha256, so it must follow every upload, even a
  # rebuild of the same version.
  cask="repos/alvaldes/homebrew-tap/contents/Casks/jump.rb"
  cask_sha="$(gh api "$cask" -q .sha)"
  gh api "$cask" -q .content | base64 -D > "$work/jump.rb"
  sed -E -e "s/^  version \".*\"$/  version \"$version\"/" \
         -e "s/^  sha256 \".*\"$/  sha256 \"$sha\"/" "$work/jump.rb" > "$work/jump.new.rb"
  if ! grep -qx "  version \"$version\"" "$work/jump.new.rb" || ! grep -qx "  sha256 \"$sha\"" "$work/jump.new.rb"; then
    echo "error: could not find the version and sha256 lines in Casks/jump.rb" >&2; exit 1
  fi
  if cmp -s "$work/jump.rb" "$work/jump.new.rb"; then
    echo "The Homebrew cask is already up to date."
  else
    gh api -X PUT "$cask" --silent \
      -f message="chore: update jump to $version" \
      -f content="$(base64 < "$work/jump.new.rb")" \
      -f sha="$cask_sha"
    echo "Updated the Homebrew cask to $version."
  fi
fi
