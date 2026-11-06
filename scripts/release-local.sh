#!/bin/bash
# Build a release on this Mac and, if asked, install it here and publish it
# on GitHub, without waiting for the Release workflow.
#
# Either path ships a version (hybrid with .github/workflows/release.yml):
#   - Bump CFBundleShortVersionString in Resources/Info.plist, commit and
#     push: the workflow builds and publishes it, as before.
#   - Or bump, commit, and run this with --publish: it builds here, pushes
#     the branch and the tag v<version> together in one atomic push, then
#     publishes the release from the DMG built here. The workflow run that
#     the push starts finds the tag already there and stops in seconds.
#
# Usage: scripts/release-local.sh [--install] [--publish] [--skip-tests]
#   (no flags)    test, then build dist/Ansomnia-<version>.dmg,
#                 dist/Ansomnia.dmg and dist/SHA256SUMS
#   --install     then install that build on this Mac
#   --publish     then publish it as the GitHub release v<version>, marked
#                 Latest, with the same files and notes as the workflow
#   --skip-tests  skip `swift test` (the workflow does not skip it)
#
# Needs Xcode, not only the Command Line Tools: the app uses SwiftUI's
# macros, which ship with Xcode. --publish also needs gh, signed in with
# push access, a clean working tree on main, and a version with no tag yet.
set -euo pipefail

PLUTIL=/usr/bin/plutil
HDIUTIL=/usr/bin/hdiutil
MKTEMP=/usr/bin/mktemp
XCODE_SELECT=/usr/bin/xcode-select

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() { echo "usage: $0 [--install] [--publish] [--skip-tests]" >&2; }
INSTALL=0
PUBLISH=0
TESTS=1
while (( $# )); do
  case "$1" in
    --install) INSTALL=1; shift ;;
    --publish) PUBLISH=1; shift ;;
    --skip-tests) TESTS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$*"; }
fail() { echo "error: $*" >&2; exit 1; }

developer_dir="$("$XCODE_SELECT" -p 2>/dev/null || true)"
if [[ -z "$developer_dir" || "$developer_dir" == /Library/Developer/CommandLineTools* ]]; then
  fail "this needs Xcode, and the active developer directory is '${developer_dir:-none}'.
The Command Line Tools alone cannot build Ansomnia (SwiftUI's macros ship with Xcode).
Install Xcode from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"
fi

VERSION="$("$PLUTIL" -extract CFBundleShortVersionString raw -o - Resources/Info.plist)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Resources/Info.plist CFBundleShortVersionString is '$VERSION', not major.minor.patch"
TAG="v$VERSION"

# Everything --publish needs is checked before the build, so a release that
# cannot go out fails in seconds, not after the tests.
if (( PUBLISH )); then
  step "Checking that $TAG can be published"
  command -v gh >/dev/null || fail "gh is not installed (brew install gh)"
  gh auth status >/dev/null 2>&1 || fail "gh is not signed in (gh auth login)"
  [[ "$(git rev-parse --abbrev-ref HEAD)" == main ]] || fail "not on main"
  [[ -z "$(git status --porcelain)" ]] || fail "the working tree has uncommitted changes; commit them first, so the release is exactly a commit"
  git fetch --quiet origin main
  git merge-base --is-ancestor origin/main HEAD || fail "origin/main has commits this branch does not; pull first"
  if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null; then
    fail "$TAG is already released; bump CFBundleShortVersionString in Resources/Info.plist"
  fi
  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    fail "a local tag $TAG exists but is not on GitHub; delete it (git tag -d $TAG) or push it yourself"
  fi
fi

if (( TESTS )); then
  step "Testing"
  swift test
fi

step "Building the DMG for $VERSION"
scripts/make-dmg.sh --output dist

if (( INSTALL )); then
  step "Installing $VERSION on this Mac"
  MNT="$("$MKTEMP" -d "${TMPDIR:-/tmp}/ansomnia-local.XXXXXX")"
  detach() { "$HDIUTIL" detach -quiet "$MNT" >/dev/null 2>&1 || true; rmdir "$MNT" 2>/dev/null || true; }
  trap detach EXIT
  "$HDIUTIL" attach -nobrowse -readonly -noautoopen -mountpoint "$MNT" "dist/Ansomnia-$VERSION.dmg" >/dev/null
  /bin/bash "$MNT/install.sh" --allow-unverified-origin --app "$MNT/Ansomnia.app"
  detach
  trap - EXIT
  /usr/bin/open "$HOME/Applications/Ansomnia.app"
fi

if (( PUBLISH )); then
  step "Pushing main and $TAG"
  git tag "$TAG" HEAD
  # One atomic push: the workflow run it starts already sees the tag.
  if ! git push --atomic origin HEAD:refs/heads/main "refs/tags/$TAG"; then
    git tag -d "$TAG" >/dev/null
    fail "the push was refused; nothing was published"
  fi

  step "Publishing $TAG"
  NOTES="$("$MKTEMP")"
  # The same notes as the Publish release step of release.yml.
  {
    echo "Ansomnia $VERSION for Apple Silicon Macs with macOS 26 or later."
    echo
    echo "**Install:** download \`Ansomnia.dmg\`, open it, then in Terminal run:"
    echo
    echo '```'
    echo 'bash "/Volumes/Ansomnia/Install Ansomnia.command"'
    echo '```'
    echo
    echo "**Update:** Settings > App > Check for updates > Download and install."
    echo
    echo "SHA-256:"
    echo
    echo '```'
    cat dist/SHA256SUMS
    echo '```'
  } > "$NOTES"
  gh release create "$TAG" \
    "dist/Ansomnia-$VERSION.dmg" dist/Ansomnia.dmg dist/SHA256SUMS \
    --verify-tag --title "Ansomnia $VERSION" --notes-file "$NOTES" --latest
  rm -f "$NOTES"
fi

echo
echo "Done: Ansomnia $VERSION in dist/."
