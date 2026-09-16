#!/bin/zsh
# Build the Debug app with xcodebuild and launch it. Regenerates the project if project.yml is newer.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -d Deskpouch.xcodeproj || project.yml -nt Deskpouch.xcodeproj/project.pbxproj ]]; then
  xcodegen generate
fi
# pipefail makes a failed build stop the script; the braces only stop grep's "no matching lines" from doing the same.
xcodebuild -scheme Deskpouch -configuration Debug -derivedDataPath build/DerivedData build | { grep -E "error|warning: |BUILD" || true; }
APP=build/DerivedData/Build/Products/Debug/Deskpouch.app
# Wait for the old instance to exit, or LaunchServices may bring it forward instead of starting the new build.
pkill -x Deskpouch || true
while pgrep -x Deskpouch >/dev/null; do sleep 0.1; done
# LaunchServices can still report the old instance for a moment after it exits (error -600): retry briefly.
for attempt in 1 2 3 4 5; do
  open "$APP" 2>/dev/null && break
  (( attempt == 5 )) && { echo "could not launch $APP" >&2; exit 1; }
  sleep 0.5
done
echo "launched $APP"
