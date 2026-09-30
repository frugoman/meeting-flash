#!/bin/zsh
# Builds, publishes the zip as a release on the public frugoman/homebrew-tap (this repo stays private),
# and updates the Homebrew cask there.
# Usage: ./release.sh 1.2.0
set -euo pipefail
cd "$(dirname "$0")"
VERSION=${1:?usage: ./release.sh <version>}
TAP=frugoman/homebrew-tap
TAG=meeting-flash-v$VERSION
ZIP=build/MeetingFlash-$VERSION.zip

./build.sh "$VERSION"
ditto -c -k --keepParent build/MeetingFlash.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

gh release create "$TAG" "$ZIP" --repo "$TAP" --title "MeetingFlash $VERSION" \
  --notes "Install with: brew install --cask frugoman/tap/meeting-flash"

TMP=$(mktemp -d)
gh repo clone "$TAP" "$TMP" -- --quiet
mkdir -p "$TMP/Casks"
cat > "$TMP/Casks/meeting-flash.rb" <<CASK
cask "meeting-flash" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$TAP/releases/download/meeting-flash-v#{version}/MeetingFlash-#{version}.zip"
  name "MeetingFlash"
  desc "Menu bar app that flashes the screen red right before a calendar meeting starts"
  homepage "https://github.com/$TAP"

  depends_on macos: :sonoma

  app "MeetingFlash.app"

  # The app is not notarized, so drop the quarantine flag to let Gatekeeper open it.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/MeetingFlash.app"],
                          writable_paths: ["MeetingFlash.app"], writable_base: :appdir
  end

  uninstall quit: "com.frugoman.meetingflash"

  zap trash: "~/Library/Preferences/com.frugoman.meetingflash.plist"

  caveats <<~EOS
    Open MeetingFlash from /Applications and allow calendar access when asked.
  EOS
end
CASK
git -C "$TMP" add Casks/meeting-flash.rb
git -C "$TMP" commit -m "meeting-flash $VERSION" --quiet
git -C "$TMP" push --quiet
rm -rf "$TMP"
echo "Released $VERSION"
