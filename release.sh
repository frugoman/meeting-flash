#!/bin/zsh
# Builds, publishes a GitHub release, and updates the Homebrew cask in frugoman/homebrew-tap.
# Usage: ./release.sh 1.2.0
set -euo pipefail
cd "$(dirname "$0")"
VERSION=${1:?usage: ./release.sh <version>}
REPO=frugoman/meeting-flash
TAP=frugoman/homebrew-tap
ZIP=build/MeetingFlash-$VERSION.zip

./build.sh "$VERSION"
ditto -c -k --keepParent build/MeetingFlash.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "MeetingFlash $VERSION" --generate-notes

TMP=$(mktemp -d)
gh repo clone "$TAP" "$TMP" -- --quiet
mkdir -p "$TMP/Casks"
cat > "$TMP/Casks/meeting-flash.rb" <<CASK
cask "meeting-flash" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/MeetingFlash-#{version}.zip"
  name "MeetingFlash"
  desc "Menu bar app that flashes the screen red right before a calendar meeting starts"
  homepage "https://github.com/$REPO"

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
